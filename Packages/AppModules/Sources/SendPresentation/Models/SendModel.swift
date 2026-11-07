import Domain
import Foundation
import Observation

@MainActor
@Observable
final class SendModel {
    private let repository: any SendRepository
    private let fileImportClient: any FileImportClient
    private let pasteboardClient: any PasteboardClient
    private let checkSessionAccess: @Sendable () throws -> Void
    private let sessionStates: (@Sendable () async -> AsyncStream<SessionState>)?
    private let sleep: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var pickedFile: (any ImportedFile)?
    @ObservationIgnored private var sessionObserver: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var draftRequestID = UUID()

    private(set) var state = SendState()

    deinit {
        sessionObserver?.cancel()
        detailTask?.cancel()
        copyFeedbackTask?.cancel()
    }

    init(
        repository: any SendRepository,
        fileImportClient: any FileImportClient,
        pasteboardClient: any PasteboardClient,
        checkSessionAccess: @escaping @Sendable () throws -> Void,
        sessionStates: (@Sendable () async -> AsyncStream<SessionState>)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.repository = repository
        self.fileImportClient = fileImportClient
        self.pasteboardClient = pasteboardClient
        self.checkSessionAccess = checkSessionAccess
        self.sessionStates = sessionStates
        self.sleep = sleep

        if let sessionStates {
            sessionObserver = Task { [weak self, sessionStates] in
                let stream = await sessionStates()
                for await sessionState in stream {
                    guard !Task.isCancelled else { return }
                    if case .unlocked = sessionState { continue }
                    self?.invalidateSession()
                    return
                }
            }
        }
    }

    func load() async {
        guard checkAccess(), !state.isLoading else { return }
        state.isLoading = true
        state.errorMessage = nil
        defer { state.isLoading = false }
        do {
            let result = try await repository.load()
            guard checkAccess() else { return }
            state.summaries = result
            if let selected = state.selectedSendID, !result.contains(where: { $0.id == selected }) {
                select(nil)
            } else if let selected = state.selectedSendID {
                await refreshSelectedDetailsAfterMutation(selected)
            }
        } catch is CancellationError {
            return
        } catch {
            guard checkAccess() else { return }
            state.errorMessage = Self.message(for: error, action: "load")
        }
    }

    func select(_ id: SendID?) {
        guard checkAccess() else { return }
        guard state.selectedSendID != id else { return }
        state.selectedSendID = id
        state.selectedDetails = nil
        state.detailErrorMessage = nil
        detailTask?.cancel()
        guard let id else { return }
        if state.summaries.first(where: { $0.id == id })?.canOpen == false {
            state.detailErrorMessage = "Couldn't decrypt this Send. Other Sends remain available."
            return
        }
        detailTask = Task { [weak self] in await self?.loadDetails(id: id) }
    }

    func beginNewTextSend() {
        guard checkAccess(), !state.isSaving else { return }
        draftRequestID = UUID()
        pickedFile = nil
        state.draft = SendDraft(contentKind: .text)
    }

    func editSend(_ id: SendID) async {
        guard checkAccess(), !state.isSaving else { return }
        let requestID = UUID()
        draftRequestID = requestID
        do {
            let draft = try await repository.editDraft(for: id)
            guard checkAccess(), !state.isSaving, draftRequestID == requestID else { return }
            pickedFile = nil
            state.draft = draft
            state.errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard checkAccess(), !state.isSaving, draftRequestID == requestID else { return }
            state.errorMessage = Self.message(for: error, action: "edit")
        }
    }

    func updateDraft(_ draft: SendDraft) {
        guard checkAccess(), !state.isSaving else { return }
        draftRequestID = UUID()
        state.draft = draft
    }

    func dismissDraft() {
        guard !state.isSaving else { return }
        draftRequestID = UUID()
        pickedFile = nil
        state.draft = nil
    }

    func pickFileSend() async {
        guard checkAccess(), !state.isSaving else { return }
        let requestID = UUID()
        draftRequestID = requestID
        do {
            guard let file = try await fileImportClient.pickFile() else { return }
            guard checkAccess(), !state.isSaving, draftRequestID == requestID else { return }
            var draft = SendDraft(contentKind: .file)
            draft.pickedFileName = file.fileName
            pickedFile = file
            state.draft = draft
            state.errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard checkAccess(), !state.isSaving, draftRequestID == requestID else { return }
            state.errorMessage = "Couldn't open the file picker. Try again."
        }
    }

    func saveDraft() async {
        guard checkAccess(), !state.isSaving, let draft = state.draft else { return }
        guard Self.isValid(draft, hasPickedFile: pickedFile != nil) else {
            state.errorMessage = "Check the required fields before saving this Send."
            return
        }
        state.isSaving = true
        draftRequestID = UUID()
        state.isUploadingFile = draft.contentKind == .file && draft.editingID == nil
        state.errorMessage = nil
        defer {
            state.isSaving = false
            state.isUploadingFile = false
        }

        // A submitted mutation belongs to the model, not to a sheet task that may disappear.
        // The session capability is rechecked by this independent task before its result reaches UI.
        let repository = repository
        let file = pickedFile
        let checkSessionAccess = checkSessionAccess
        let operation = Task {
            let snapshot = try await repository.save(draft, file: file)
            try checkSessionAccess()
            return snapshot
        }
        do {
            let snapshot = try await operation.value
            state.summaries = snapshot
            pickedFile = nil
            state.draft = nil
            if let selected = state.selectedSendID, !snapshot.contains(where: { $0.id == selected }) {
                select(nil)
            } else if let selected = state.selectedSendID {
                await refreshSelectedDetailsAfterMutation(selected)
            }
        } catch is CancellationError {
            if !Task.isCancelled { invalidateSession() }
        } catch {
            let repositoryError = error as? SendRepositoryError
            let committed: Bool
            switch repositoryError {
            case .fileUploadFailed, .committedButFollowUpFailed, .committedButCleanupFailed, .fileUploadAndCleanupFailed, .mutationOutcomeUnknown, .mutationOutcomeUnknownAndCleanupFailed:
                committed = true
                // Confirm the same submitted draft before a UI-cancellation check can return.
                // isSaving prevents replacement while this operation is in flight.
                pickedFile = nil
                state.draft = nil
            default: committed = false
            }
            guard checkAccess() else { return }
            var message = Self.message(for: error, action: "save")
            if committed {
                if !(await refreshAfterCommittedFailure()) {
                    message += " The list could not be refreshed; verify the server state before creating another Send."
                }
            }
            state.errorMessage = message
        }
    }

    func requestDelete(_ id: SendID) {
        guard checkAccess(), !state.isDeleting, state.summaries.contains(where: { $0.id == id }) else { return }
        state.pendingDeleteID = id
    }

    func cancelDelete() {
        guard !state.isDeleting else { return }
        state.pendingDeleteID = nil
    }

    func confirmDelete() async {
        guard checkAccess(), !state.isDeleting, let id = state.pendingDeleteID else { return }
        state.isDeleting = true
        state.errorMessage = nil
        defer {
            state.isDeleting = false
            state.pendingDeleteID = nil
        }
        let repository = repository
        let checkSessionAccess = checkSessionAccess
        let operation = Task {
            let snapshot = try await repository.delete(id: id)
            try checkSessionAccess()
            return snapshot
        }
        do {
            let snapshot = try await operation.value
            state.summaries = snapshot
            if state.selectedSendID == id { select(nil) }
        } catch is CancellationError {
            if !Task.isCancelled { invalidateSession() }
        } catch {
            guard checkAccess() else { return }
            state.errorMessage = Self.message(for: error, action: "delete")
        }
    }

    func copyLink(for id: SendID) async {
        guard checkAccess() else { return }
        do {
            let link = try await repository.shareLink(for: id)
            guard checkAccess() else { return }
            pasteboardClient.copySecret(link.absoluteString)
            let feedbackID = UUID()
            state.copyFeedbackID = feedbackID
            copyFeedbackTask?.cancel()
            copyFeedbackTask = Task { [weak self, sleep] in
                do { try await sleep(.seconds(3)) } catch { return }
                guard !Task.isCancelled else { return }
                guard let self, state.copyFeedbackID == feedbackID else { return }
                state.copyFeedbackID = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard checkAccess() else { return }
            state.linkErrorMessage = Self.message(for: error, action: "link")
        }
    }

    func dismissError() { state.errorMessage = nil }
    func dismissDetailError() { state.detailErrorMessage = nil }
    func dismissLinkError() { state.linkErrorMessage = nil }

    private func loadDetails(id: SendID) async {
        do {
            let details = try await repository.details(for: id)
            guard checkAccess(), state.selectedSendID == id else { return }
            state.selectedDetails = details
        } catch is CancellationError {
            return
        } catch {
            guard checkAccess(), state.selectedSendID == id else { return }
            state.detailErrorMessage = Self.message(for: error, action: "decrypt")
        }
    }

    private func refreshAfterCommittedFailure() async -> Bool {
        let repository = repository
        let checkSessionAccess = checkSessionAccess
        let refresh = Task {
            let snapshot = try await repository.load()
            try checkSessionAccess()
            return snapshot
        }
        do {
            state.summaries = try await refresh.value
            return true
        } catch is CancellationError {
            if !Task.isCancelled { invalidateSession() }
            return false
        } catch {
            guard checkAccess() else { return false }
            return false
        }
    }

    private func refreshSelectedDetailsAfterMutation(_ id: SendID) async {
        let repository = repository
        let checkSessionAccess = checkSessionAccess
        let refresh = Task {
            let details = try await repository.details(for: id)
            try checkSessionAccess()
            return details
        }
        do {
            let details = try await refresh.value
            guard state.selectedSendID == id else { return }
            state.selectedDetails = details
            state.detailErrorMessage = nil
        } catch is CancellationError {
            if !Task.isCancelled { invalidateSession() }
        } catch {
            guard checkAccess(), state.selectedSendID == id else { return }
            state.selectedDetails = nil
            state.detailErrorMessage = Self.message(for: error, action: "decrypt")
        }
    }

    private func checkAccess() -> Bool {
        do { try checkSessionAccess(); return true }
        catch {
            // Cancellation of an ordinary SwiftUI consumer is not proof the session was revoked.
            if !Task.isCancelled { invalidateSession() }
            return false
        }
    }

    private func invalidateSession() {
        draftRequestID = UUID()
        detailTask?.cancel()
        copyFeedbackTask?.cancel()
        pickedFile = nil
        state = SendState()
        let repository = repository
        Task { await repository.lock() }
    }

    private static func isValid(_ draft: SendDraft, hasPickedFile: Bool) -> Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if draft.contentKind == .text, draft.text.isEmpty { return false }
        if draft.contentKind == .file, draft.editingID == nil, !hasPickedFile { return false }
        if draft.hasPasswordProtection, !draft.hadExistingPassword, draft.password.isEmpty { return false }
        if draft.hasMaxAccessCount, draft.maxAccessCount <= 0 || UInt32(exactly: draft.maxAccessCount) == nil { return false }
        if !draft.deletionDate.timeIntervalSince1970.isFinite { return false }
        if draft.hasExpirationDate, !draft.expirationDate.timeIntervalSince1970.isFinite { return false }
        return true
    }

    private static func message(for error: Error, action: String) -> String {
        if let authorization = error as? SessionAuthorizationError { return authorization.errorDescription ?? "Session authorization failed." }
        guard let error = error as? SendRepositoryError else {
            return action == "decrypt" ? "Couldn't decrypt this Send." : "Couldn't complete this Send action. Try again."
        }
        switch error {
        case .sessionUnavailable: return "Your session is no longer available. Unlock the app and try again."
        case .server(let status): return "The server couldn't \(action) this Send (response \(status))."
        case .cryptoFailure: return "Couldn't decrypt or encrypt this Send. Check the vault and try again."
        case .itemUnavailable: return "This Send is no longer available. Refresh the list and try again."
        case .invalidDraft: return "Check the required fields before saving this Send."
        case .fileUploadFailed: return "The Send was created, but its encrypted file upload failed. Do not retry; refresh the list and verify it first."
        case .committedButFollowUpFailed: return "The Send was updated, but the follow-up password change failed. The list was refreshed; verify its access settings before editing again."
        case .filePreparationFailed: return "Couldn't prepare the encrypted file. Check file access and available disk space."
        case .temporaryCleanupFailed: return "File preparation failed and temporary files could not be removed. Lock the app to retry cleanup before another save."
        case .committedButCleanupFailed: return "The Send was created and its file uploaded, but temporary-file cleanup failed. Lock the app to retry cleanup; do not upload it again."
        case .fileUploadAndCleanupFailed: return "The Send was created, but its file upload and temporary-file cleanup failed. Lock the app to retry cleanup, then verify the server state; do not create it again."
        case .invalidResponse: return "The server returned an invalid response while trying to \(action) this Send."
        case .mutationOutcomeUnknown: return "The server may have saved this Send. Do not create it again before checking the refreshed list and server state."
        case .mutationOutcomeUnknownAndCleanupFailed: return "The server may have saved this Send and temporary-file cleanup failed. Lock the app to retry cleanup; verify the server state before creating another Send."
        }
    }
}
