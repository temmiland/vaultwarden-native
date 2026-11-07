import Domain
import Foundation
import Observation

/// The screen model owns presentation and cancellable detail tasks, never the vault's mutable backing.
@MainActor
@Observable
public final class VaultModel {
    private let repository: any VaultRepository
    private let generator: any PasswordGenerating
    private let fileImportClient: any FileImportClient
    private let removeTemporaryFile: @Sendable (URL) async throws -> Void
    private let checkSessionAccess: @Sendable () throws -> Void
    private let onLogout: () -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var editorRequest: Task<Void, Never>?
    @ObservationIgnored private var editorRequestID: UUID?

    public init(
        repository: any VaultRepository,
        generator: any PasswordGenerating,
        fileImportClient: any FileImportClient,
        removeTemporaryFile: @escaping @Sendable (URL) async throws -> Void,
        checkSessionAccess: @escaping @Sendable () throws -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.repository = repository; self.generator = generator
        self.fileImportClient = fileImportClient; self.removeTemporaryFile = removeTemporaryFile
        self.checkSessionAccess = checkSessionAccess; self.onLogout = onLogout
        state = VaultState()
    }

    public internal(set) var state: VaultState

    isolated deinit {
        observation?.cancel()
        editorRequest?.cancel()
    }

    public func send(_ action: VaultAction) {
        guard hasSessionAccess() else { return }
        switch action {
        case let .searchQueryChanged(query): state.searchQuery = query; reconcile()
        case let .filterSelected(filter): state.filter = filter; reconcile()
        case let .itemSelected(id):
            if state.selectedItemID != id { state.clearDetailSupplements() }
            state.selectedItemID = id; reconcile()
        case let .addItemTapped(kind):
            guard kind.supportsEditing else { return }
            cancelEditorRequest()
            state.sheet = .edit(VaultItemDraft(kind: kind, folderID: currentFolderFilterID))
        case let .editItemTapped(id): openEditor(id)
        case .sheetDismissed: cancelEditorRequest(); state.sheet = nil
        case let .draftChanged(draft):
            state.reconcileEditingAccess()
            guard let current = state.sheet?.draft, current.editingID == draft.editingID,
                  current.kind == draft.kind, current.baseRevision == draft.baseRevision else { return }
            state.sheet = .edit(draft)
        case let .deleteItemTapped(id):
            guard state.snapshot.details[id]?.permissions.canDelete == true else { return }
            state.pendingDeleteID = id
        case .deleteCancelled: state.pendingDeleteID = nil
        case let .deleteAttachmentTapped(reference):
            guard let detail = state.selectedItem, detail.id == reference.cipherID,
                  detail.permissions.canEdit, detail.attachments.contains(where: { $0.reference == reference }) else { return }
            state.pendingAttachmentDelete = reference
        case .deleteAttachmentCancelled: state.pendingAttachmentDelete = nil
        case .previewDismissed: discardPreview()
        case let .generatorPresentedChanged(value): state.isGeneratorPresented = value
        case let .generatorOptionsChanged(options):
            state.generatorOptions = options; state.generatedPassword = ""; state.generatorErrorMessage = nil
        case .errorDismissed: state.errorMessage = nil
        case .passkeyRecoveryReviewDismissed: state.passkeyRecoveryReview = nil
        case .logoutTapped: onLogout()
        }
    }

    public func perform(_ effect: VaultEffect) async {
        guard hasSessionAccess() else { return }
        await startObservation()
        switch effect {
        case .loadVault: await loadVault()
        case .reviewPasskeyRegistrationRecovery: await reviewPasskeyRecovery()
        case let .abandonPasskeyRegistrationRecovery(review): await abandonPasskeyRecovery(review)
        case .saveDraft: await saveDraft()
        case .confirmDelete: await confirmDelete()
        case .regeneratePassword: regeneratePassword()
        case let .refreshTotp(context): await refreshTotp(context)
        case let .loadPasskeys(context): await loadPasskeys(context)
        case let .pickAttachment(id): await pickAttachment(id)
        case let .downloadAttachment(reference): await downloadAttachment(reference)
        case .confirmDeleteAttachment: await confirmDeleteAttachment()
        }
        _ = hasSessionAccess()
    }

    private func startObservation() async {
        guard observation == nil else { return }
        // Register before launching the consumer so no committed update can be missed.
        let stream = await repository.observeVault()
        guard observation == nil, hasSessionAccess() else { return }
        observation = Task { [weak self] in
            for await snapshot in stream {
                guard !Task.isCancelled, self?.acceptObservedSnapshot(snapshot) == true else { return }
            }
        }
    }

    private func acceptObservedSnapshot(_ snapshot: VaultSnapshot) -> Bool {
        guard hasSessionAccess() else { return false }
        accept(snapshot)
        return true
    }

    private func accept(_ snapshot: VaultSnapshot) {
        guard snapshot.revision >= state.snapshot.revision else { return }
        state.snapshot = snapshot; reconcile()
        if state.passkeyRecoveryReview?.vaultRevision != snapshot.revision ||
            !snapshot.warnings.contains(.passkeyRegistrationRecoveryPending) || snapshot.isStale ||
            snapshot.projectionStatus != .current(revision: snapshot.revision) || state.unavailableItemCount > 0 {
            state.passkeyRecoveryReview = nil
        }
    }

    private func refreshPresentation() async throws {
        let snapshot = await repository.currentSnapshot()
        try checkSessionAccess(); accept(snapshot)
    }

    private func reconcile() {
        state.reconcileSelection()
        if let context = state.previewContext,
           state.selectedItem?.context != context || state.selectedItem?.permissions.canViewSecrets != true { discardPreview(
        ) }
    }

    public func invalidateSession() {
        observation?.cancel(); observation = nil
        cancelEditorRequest(); discardPreview(); state = VaultState(); state.isLoading = false
    }

    private func hasSessionAccess() -> Bool {
        // A disappearing detail task is not a revoked session. Its cancellation must not clear
        // the shared screen's credentials or stop another consumer's observation.
        guard !Task.isCancelled else { return false }
        do { try checkSessionAccess(); return true }
        catch { invalidateSession(); return false }
    }

    private func cancelEditorRequest() {
        editorRequest?.cancel(); editorRequest = nil; editorRequestID = nil
    }

    private func openEditor(_ id: CipherID) {
        guard state.snapshot.details[id]?.permissions.canEdit == true else { return }
        cancelEditorRequest()
        let requestID = UUID(); editorRequestID = requestID
        editorRequest = Task { [weak self, repository] in
            do {
                let draft = try await repository.makeDraft(for: id)
                guard let self, editorRequestID == requestID, hasSessionAccess() else { return }
                guard state.snapshot.details[id]?.context.revision == draft.baseRevision,
                      state.snapshot.details[id]?.permissions.canEdit == true else { return }
                state.sheet = .edit(draft)
            } catch is CancellationError {} catch {
                guard let self, editorRequestID == requestID, hasSessionAccess() else { return }
                state.errorMessage = "This item can't be edited safely. Sync your vault and try again."
            }
        }
    }

    private func loadVault() async {
        state.passkeyRecoveryReview = nil
        state.isLoading = true; state.errorMessage = nil
        defer { state.isLoading = false }
        do { try await repository.sync(); try await refreshPresentation() }
        catch is CancellationError {} catch {
            guard hasSessionAccess() else { return }
            state.errorMessage = (error as? SessionAuthorizationError)?.errorDescription ?? "Couldn't sync your vault. Please try again."
        }
    }

    private func reviewPasskeyRecovery() async {
        guard !state.isPasskeyRecoveryBusy, !state.isLoading else { return }
        state.isPasskeyRecoveryBusy = true; state.errorMessage = nil; state.passkeyRecoveryReview = nil
        defer { state.isPasskeyRecoveryBusy = false }
        do {
            let review = try await repository.preparePasskeyRegistrationRecoveryReview()
            try checkSessionAccess(); try Task.checkCancellation()
            guard review.vaultRevision == state.snapshot.revision,
                  state.loadWarnings.contains(.passkeyRegistrationRecoveryPending), !state.snapshot.isStale,
                  !state.isLoading, state.unavailableItemCount == 0,
                  state.snapshot.projectionStatus == .current(revision: state.snapshot.revision) else { return }
            state.passkeyRecoveryReview = review
        } catch is CancellationError {} catch {
            if hasSessionAccess() { state.errorMessage = recoveryErrorMessage(error) }
        }
    }

    private func abandonPasskeyRecovery(_ review: PasskeyRegistrationRecoveryReview) async {
        guard !state.isPasskeyRecoveryBusy, !state.isLoading, state.passkeyRecoveryReview == review,
              review.readiness == .ready else { return }
        state.isPasskeyRecoveryBusy = true; state.errorMessage = nil
        defer { state.isPasskeyRecoveryBusy = false }
        do {
            try await repository.abandonPasskeyRegistrationRecovery(review)
            // Remove the same confirmed review before checking UI cancellation, just like a
            // confirmed create draft. A stale prompt must not invite another acknowledgment.
            if state.passkeyRecoveryReview == review { state.passkeyRecoveryReview = nil }
            try checkSessionAccess(); try Task.checkCancellation()
            try await refreshPresentation()
        } catch is CancellationError {} catch {
            if hasSessionAccess() {
                state.passkeyRecoveryReview = nil
                state.errorMessage = recoveryErrorMessage(error)
            }
        }
    }

    private func recoveryErrorMessage(_ error: any Error) -> String {
        switch error as? PasskeyRegistrationReviewError {
        case .syncRequired: "Finish a full sync with working AutoFill and no unavailable items before reviewing this write."
        case .freshUnlockRequired: "Lock and unlock the app, then sync again before abandoning this registration's tracking."
        case .legacyOriginUnknown: "This older recovery record has no unlock lineage. Keep it blocked and verify the credential in an official client; it cannot be safely abandoned here."
        case .reviewChanged: "The recovery record or vault changed. Sync and review it again; no server write was retried."
        default: "Couldn't update passkey recovery tracking. Sync and review it again; no server write was retried."
        }
    }

    private func saveDraft() async {
        guard !state.isSavingDraft, let draft = state.sheet?.draft else { return }
        state.isSavingDraft = true; state.errorMessage = nil
        defer { state.isSavingDraft = false }
        do {
            let id = try await repository.save(draft)
            // An acknowledged create is never retryable, including cancellation of this UI task.
            if state.sheet?.draft == draft { state.sheet = nil }
            try checkSessionAccess()
            state.selectedItemID = id
            try await refreshPresentation()
        } catch is CancellationError {} catch VaultRepositoryError.committedButRefreshFailed {
            if state.sheet?.draft == draft { state.sheet = nil }
            guard hasSessionAccess() else { return }
            state.errorMessage = "The item was saved, but couldn't be refreshed. Sync before editing it again."
        } catch {
            guard hasSessionAccess() else { return }
            state.reconcileEditingAccess()
            state.errorMessage = (error as? SessionAuthorizationError)?.errorDescription ?? "Couldn't save this item safely. Sync and reopen the editor before retrying."
        }
    }

    private func confirmDelete() async {
        guard let id = state.pendingDeleteID, let detail = state.snapshot.details[id], detail.permissions.canDelete else {
            state.pendingDeleteID = nil; return
        }
        defer { if state.pendingDeleteID == id { state.pendingDeleteID = nil } }
        do { try await repository.delete(detail.context); try await refreshPresentation() }
        catch is CancellationError {} catch {
            if hasSessionAccess() { state.errorMessage = (error as? SessionAuthorizationError)?.errorDescription ?? "Couldn't delete this item safely. Sync before retrying." }
        }
    }

    private func regeneratePassword() {
        state.generatedPassword = ""; state.generatorErrorMessage = nil
        do { state.generatedPassword = try generator.generatePassword(options: state.generatorOptions) }
        catch {
            switch error as? PasswordGenerationError {
            case .invalidLength: state.generatorErrorMessage = "Choose a password length between 5 and 128."
            case .noCharacterClasses: state.generatorErrorMessage = "Select at least one character type."
            case .invalidMinimumCounts: state.generatorErrorMessage = "Minimum counts must be between 0 and 9."
            case .minimumCountsExceedLength: state.generatorErrorMessage = "Increase the length to fit the minimum character counts."
            default: state.generatorErrorMessage = "Couldn't generate a password. Please try again."
            }
        }
    }

    private func refreshTotp(_ context: VaultItemContext) async {
        guard state.selectedItem?.context == context else { return }
        do {
            let value = try await repository.oneTimeCode(for: context)
            guard hasSessionAccess(), state.selectedItem?.context == context else { return }
            state.oneTimeCode = value
        } catch { if state.selectedItem?.context == context { state.oneTimeCode = nil } }
    }

    private func loadPasskeys(_ context: VaultItemContext) async {
        guard state.selectedItem?.context == context else { return }
        do {
            let values = try await repository.passkeys(for: context)
            guard hasSessionAccess(), state.selectedItem?.context == context else { return }
            state.passkeyContext = context; state.passkeySummaries = values
        } catch {
            if state.selectedItem?.context == context { state.passkeyContext = nil; state.passkeySummaries = [] }
        }
    }

    private var currentFolderFilterID: FolderID? {
        if case let .folder(id) = state.filter { return id }; return nil
    }

    private func pickAttachment(_ id: CipherID) async {
        guard !state.isAttachmentBusy, let detail = state.snapshot.details[id], detail.permissions.canEdit else { return }
        state.isAttachmentBusy = true; state.errorMessage = nil
        defer { state.isAttachmentBusy = false }
        do {
            guard let file = try await fileImportClient.pickFile() else { return }
            try checkSessionAccess()
            try await repository.uploadAttachment(to: detail.context, file: file)
            try await refreshPresentation()
        } catch is CancellationError {} catch {
            if hasSessionAccess() { state.errorMessage = attachmentErrorMessage(error) }
        }
    }

    private func downloadAttachment(_ reference: VaultAttachmentReference) async {
        guard !state.isAttachmentBusy, let detail = state.selectedItem, detail.id == reference.cipherID,
              detail.permissions.canViewSecrets else { return }
        state.isAttachmentBusy = true; state.errorMessage = nil
        defer { state.isAttachmentBusy = false }
        var downloaded: URL?
        do {
            try await cleanUpPreviewFile()
            let url = try await repository.downloadAttachment(reference, context: detail.context)
            downloaded = url
            try checkSessionAccess()
            guard state.selectedItem?.context == detail.context,
                  state.selectedItem?.permissions.canViewSecrets == true else { throw CancellationError() }
            state.previewContext = detail.context; state.previewURL = url; downloaded = nil
        } catch is CancellationError {} catch {
            if hasSessionAccess() { state.errorMessage = attachmentErrorMessage(error) }
        }
        if let downloaded { await removePreview(downloaded) }
    }

    private func confirmDeleteAttachment() async {
        guard !state.isAttachmentBusy, let reference = state.pendingAttachmentDelete else { return }
        guard let detail = state.selectedItem, detail.id == reference.cipherID, detail.permissions.canEdit,
              detail.attachments.filter({ $0.reference == reference }).count == 1 else {
            state.pendingAttachmentDelete = nil
            return
        }
        state.isAttachmentBusy = true
        defer {
            state.isAttachmentBusy = false
            if state.pendingAttachmentDelete == reference { state.pendingAttachmentDelete = nil }
        }
        do { try await repository.deleteAttachment(reference, context: detail.context); try await refreshPresentation() }
        catch is CancellationError {} catch {
            if hasSessionAccess() { state.errorMessage = attachmentErrorMessage(error) }
        }
    }

    private func attachmentErrorMessage(_ error: Error) -> String {
        if let authorization = error as? SessionAuthorizationError { return authorization.errorDescription ?? "Session authorization failed." }
        return switch error as? VaultRepositoryError {
        case .committedButCleanupFailed:
            "The attachment was saved, but temporary files couldn't be removed. Don't repeat the upload. Lock the vault to retry cleanup."
        case .temporaryCleanupFailed:
            "Temporary attachment files couldn't be securely removed. Lock the vault to retry cleanup, then sync before repeating the operation."
        case .committedButRefreshFailed:
            "The server accepted the attachment operation, but it couldn't finish locally. Sync before repeating it."
        default:
            "The attachment operation couldn't finish safely. Sync before retrying."
        }
    }

    private func detachPreviewURL() -> URL? {
        let url = state.previewURL; state.previewURL = nil; state.previewContext = nil; return url
    }

    private func cleanUpPreviewFile() async throws {
        if let url = detachPreviewURL() { try await removeTemporaryFile(url) }
    }

    private func removePreview(_ url: URL) async {
        do { try await removeTemporaryFile(url) }
        catch {
            state.errorMessage = "Couldn't securely remove temporary attachment files. Lock the vault to retry cleanup."
        }
    }

    private func discardPreview() {
        guard let url = detachPreviewURL() else { return }
        Task { await removePreview(url) }
    }
}
