import BitwardenSDKAdapter
import Domain
import Foundation
import Observation
import Testing
@testable import VaultPresentation

/// Model behavior uses the public repository port. Crypto/HTTP order is tested separately against
/// the actual SDK source, rather than preserving a simulated legacy service graph in this suite.
@MainActor
@Suite
struct VaultModelTests {
    @Test
    func disabledSuggestionsDoNotWarnAboutAHealthyVaultButStaleCachesStillDo() {
        var state = VaultState()
        let cases: [(VaultProjectionStatus, Bool)] = [
            (.current(revision: 7), false), (.suggestionsDisabled(revision: 7), false),
            (.current(revision: 6), true), (.suggestionsDisabled(revision: 6), true),
            (.stale, true), (.unavailable, true),
        ]
        for (status, attention) in cases {
            state.snapshot = VaultSnapshot(
                revision: 7, items: [], lastSuccessfulSync: .distantPast,
                isStale: false, projectionStatus: status
            )
            #expect(state.needsSyncAttention == attention)
        }
        state.snapshot = VaultSnapshot(
            revision: 7, items: [], lastSuccessfulSync: .distantPast,
            isStale: true, projectionStatus: .suggestionsDisabled(revision: 7)
        )
        #expect(state.needsSyncAttention)
    }

    @Test
    func refreshRecoveryShowsSignInGuidanceInsteadOfAnEndlessSyncRetry() async {
        let (model, repository) = make(VaultSnapshot(revision: 1, items: [], lastSuccessfulSync: nil, isStale: true))
        repository.syncError = SessionAuthorizationError.refreshRecoveryRequired
        await model.perform(.loadVault)
        #expect(model.state.errorMessage == SessionAuthorizationError.refreshRecoveryRequired.errorDescription)
        #expect(!model.state.isLoading)
    }

    private func makeRecoveryModel(
        gate: ProcessorAccessGate = ProcessorAccessGate(),
        readiness: PasskeyRecoveryReviewReadiness = .ready
    )
        -> (VaultModel, ProcessorRepository, PasskeyRegistrationRecoveryReview) {
        let snapshot = VaultSnapshot(
            revision: 1,
            items: [],
            lastSuccessfulSync: Date(),
            isStale: false,
            warnings: [.passkeyRegistrationRecoveryPending],
            projectionStatus: .current(revision: 1)
        )
        let (model, repository) = make(snapshot, gate: gate)
        let review = PasskeyRegistrationRecoveryReview(
            vaultRevision: 1,
            relyingPartyIdentifier: "example.com",
            serverConfirmed: false,
            readiness: readiness
        )
        model.state.isLoading = false; repository.recoveryReview = review
        return (model, repository, review)
    }

    @Test
    func preparingAndDismissingRecoveryReviewNeverAcknowledgesOrWrites() async {
        let (model, repository, review) = makeRecoveryModel()
        await model.perform(.reviewPasskeyRegistrationRecovery)
        #expect(model.state.passkeyRecoveryReview == review)
        #expect(repository.recoveryAcknowledgments.isEmpty && repository.saved.isEmpty)
        model.send(.passkeyRecoveryReviewDismissed)
        #expect(model.state.passkeyRecoveryReview == nil)
        #expect(repository.recoveryAcknowledgments.isEmpty)
    }

    @Test(arguments: [PasskeyRecoveryReviewReadiness.requiresFreshUnlock, .legacyOriginUnknown])
    func informationalUnsafeReviewCannotReachTheAcknowledgmentPort(_ readiness: PasskeyRecoveryReviewReadiness) async {
        let (model, repository, review) = makeRecoveryModel(readiness: readiness)
        await model.perform(.reviewPasskeyRegistrationRecovery)
        await model.perform(.abandonPasskeyRegistrationRecovery(review))
        #expect(model.state.passkeyRecoveryReview == review)
        #expect(repository.recoveryAcknowledgments.isEmpty)
    }

    @Test
    func duplicateAcknowledgmentCannotSubmitWhileFirstIsAwaiting() async {
        let (model, repository, review) = makeRecoveryModel(), gate = ProcessorPause()
        repository.beforeRecoveryAcknowledgment = { await gate.pause() }
        await model.perform(.reviewPasskeyRegistrationRecovery)
        let task = Task { await model.perform(.abandonPasskeyRegistrationRecovery(review)) }
        await gate.waitUntilPaused()
        await model.perform(.abandonPasskeyRegistrationRecovery(review))
        #expect(repository.recoveryAcknowledgments == [review])
        gate.resume(); await task.value
        #expect(model.state.passkeyRecoveryReview == nil && !model.state.isPasskeyRecoveryBusy)
        #expect(!model.state.loadWarnings.contains(.passkeyRegistrationRecoveryPending))
        #expect(repository.saved.isEmpty)
    }

    @Test
    func confirmedLocalAcknowledgmentClosesItsReviewBeforeUICancellationCheck() async {
        let (model, repository, review) = makeRecoveryModel(), gate = ProcessorPause()
        repository.beforeRecoveryAcknowledgment = { await gate.pause() }
        await model.perform(.reviewPasskeyRegistrationRecovery)
        let task = Task { await model.perform(.abandonPasskeyRegistrationRecovery(review)) }
        await gate.waitUntilPaused(); task.cancel(); gate.resume(); await task.value
        #expect(model.state.passkeyRecoveryReview == nil && !model.state.isPasskeyRecoveryBusy)
        #expect(repository.recoveryAcknowledgments == [review])
    }

    @Test(arguments: ["lock", "sync"])
    func lateReviewCannotReopenAfterRevocationOrReload(_ reason: String) async {
        let access = ProcessorAccessGate(), gate = ProcessorPause()
        let (model, repository, _) = makeRecoveryModel(gate: access)
        repository.beforeRecoveryReview = { await gate.pause() }
        let task = Task { await model.perform(.reviewPasskeyRegistrationRecovery) }
        await gate.waitUntilPaused()
        if reason == "lock" { access.revoke(); model.invalidateSession() }
        else {
            repository.syncOutput = VaultSnapshot(
                revision: 2,
                items: [],
                lastSuccessfulSync: Date(),
                isStale: false,
                warnings: [.passkeyRegistrationRecoveryPending],
                projectionStatus: .current(revision: 2)
            )
            await model.perform(.loadVault)
        }
        gate.resume(); await task.value
        #expect(model.state.passkeyRecoveryReview == nil && !model.state.isPasskeyRecoveryBusy)
        #expect(repository.recoveryAcknowledgments.isEmpty)
    }

    @Test
    func acknowledgmentFailureClosesConsentAndKeepsWarningWithoutRawDiagnostics() async {
        let (model, repository, review) = makeRecoveryModel()
        // First obtain a valid prompt, then make the storage/acknowledgment fail.
        await model.perform(.reviewPasskeyRegistrationRecovery)
        repository.recoveryError = ProcessorFixtureError.secretDiagnostic
        await model.perform(.abandonPasskeyRegistrationRecovery(review))
        #expect(model.state.passkeyRecoveryReview == nil)
        #expect(model.state.loadWarnings.contains(.passkeyRegistrationRecoveryPending))
        #expect(model.state.errorMessage?.contains("secretDiagnostic") == false)
        #expect(model.state.errorMessage?.contains("no server write was retried") == true)
        await model.perform(.abandonPasskeyRegistrationRecovery(review))
        #expect(repository.recoveryAcknowledgments == [review])
    }

    private func make(
        _ snapshot: VaultSnapshot = vaultSnapshot(),
        gate: ProcessorAccessGate = ProcessorAccessGate(),
        generator: any PasswordGenerating = ProcessorGenerator(),
        removeTemporaryFile: @escaping @Sendable (URL) async throws -> Void = { _ in },
        fileImportClient: (any FileImportClient)? = nil
    )
        -> (VaultModel, ProcessorRepository) {
        let repository = ProcessorRepository(snapshot: snapshot)
        let model = VaultModel(
            repository: repository,
            generator: generator,
            fileImportClient: fileImportClient ?? MockFileImportClient(
                file: MockImportedFile(url: URL(fileURLWithPath: "/tmp/imported.bin"))
            ),
            removeTemporaryFile: removeTemporaryFile,
            checkSessionAccess: { try gate.check() },
            onLogout: {}
        )
        model.state.snapshot = snapshot
        return (model, repository)
    }

    @Test
    func presentationStatePublishesChangesThroughObservation() {
        let (model, _) = make()
        let changeFlag = ObservationChangeFlag()
        let initialQuery = withObservationTracking {
            model.state.searchQuery
        } onChange: {
            changeFlag.mark()
        }

        model.send(.searchQueryChanged("example"))

        #expect(initialQuery.isEmpty)
        #expect(changeFlag.didChange)
    }

    private func openEditor(_ model: VaultModel, _ id: String = "cipher-1") async throws {
        model.send(.editItemTapped(CipherID(rawValue: id)))
        for _ in 0 ..< 200 where model.state.sheet == nil { await Task.yield() }
        _ = try #require(model.state.sheet)
    }

    @Test
    func createAndUpdateUseRepositoryResultsWithoutPatchingSDKArrays() async throws {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()]))
        try await openEditor(model)
        var draft = try #require(model.state.sheet?.draft)
        draft.name = "Renamed"
        model.send(.draftChanged(draft))
        await model.perform(.saveDraft)
        #expect(repository.saved == [draft])
        #expect(model.state.visibleItems.map(\.name) == ["Renamed"])
        #expect(model.state.sheet == nil)
        model.send(.addItemTapped(.login))
        await model.perform(.saveDraft)
        #expect(repository.saved.count == 2)
        #expect(model.state.selectedItemID == CipherID(rawValue: "created"))
    }

    @Test
    func saveFailureKeepsDraftAndHidesRawDiagnostics() async throws {
        let (model, repository) = make()
        repository.saveError = ProcessorFixtureError.secretDiagnostic
        model.send(.addItemTapped(.login))
        let draft = try #require(model.state.sheet?.draft)
        await model.perform(.saveDraft)
        #expect(model.state.sheet?.draft == draft)
        #expect(model.state.errorMessage != nil)
        #expect(model.state.errorMessage?.contains("secretDiagnostic") == false)
        #expect(!model.state.isSavingDraft)
    }

    @Test
    func confirmedWriteFailureDoesNotOfferAnotherCreate() async {
        let (model, repository) = make()
        repository.saveError = VaultRepositoryError.committedButRefreshFailed
        model.send(.addItemTapped(.login))
        await model.perform(.saveDraft)
        await model.perform(.saveDraft)
        #expect(repository.saved.count == 1)
        #expect(model.state.sheet == nil)
        #expect(model.state.errorMessage?.contains("was saved") == true)
    }

    @Test
    func duplicateSaveDoesNotSubmitTwice() async {
        let (model, repository) = make()
        let pause = ProcessorPause()
        repository.beforeSave = { await pause.pause() }
        model.send(.addItemTapped(.login))
        let first = Task { await model.perform(.saveDraft) }
        await pause.waitUntilPaused()
        await model.perform(.saveDraft)
        #expect(repository.saved.count == 1)
        pause.resume()
        await first.value
        #expect(!model.state.isSavingDraft)
    }

    @Test
    func successfulCreateClosesDraftEvenWhenItsUIConsumerWasCancelled() async {
        let (model, repository) = make()
        let pause = ProcessorPause()
        repository.beforeSave = { await pause.pause() }
        model.send(.addItemTapped(.login))
        let save = Task { await model.perform(.saveDraft) }
        await pause.waitUntilPaused()
        save.cancel(); pause.resume()
        await save.value
        #expect(model.state.sheet == nil)
        #expect(repository.saved.count == 1)
    }

    @Test
    func confirmedFailureAlsoClosesTheDraftOfACancelledUIConsumer() async {
        let (model, repository) = make()
        let pause = ProcessorPause()
        repository.beforeSave = { await pause.pause() }
        repository.saveError = VaultRepositoryError.committedButRefreshFailed
        model.send(.addItemTapped(.login))
        let save = Task { await model.perform(.saveDraft) }
        await pause.waitUntilPaused()
        save.cancel(); pause.resume(); await save.value
        #expect(model.state.sheet == nil)
        #expect(repository.saved.count == 1)
    }

    @Test
    func downloadFinishingAfterNavigationIsRemovedInsteadOfBecomingAPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "model-preview-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let url = root.appendingPathComponent("preview.bin")
        try Data([0x01]).write(to: url)
        let (model, repository) = make(
            vaultSnapshot(ciphers: [.fixture(), .fixture(id: "cipher-2")]),
            removeTemporaryFile: { url in try FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        )
        repository.downloadURL = url
        let pause = ProcessorPause(); repository.beforeDetail = { await pause.pause() }
        model.send(.itemSelected(CipherID(rawValue: "cipher-1")))
        let download = Task { await model.perform(.downloadAttachment(attachmentReference())) }
        await pause.waitUntilPaused()
        model.send(.itemSelected(CipherID(rawValue: "cipher-2")))
        pause.resume(); await download.value
        #expect(model.state.previewURL == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test
    func lateSaveCannotCloseAReplacementDraft() async throws {
        let (model, repository) = make()
        let pause = ProcessorPause()
        repository.beforeSave = { await pause.pause() }
        model.send(.addItemTapped(.login))
        let save = Task { await model.perform(.saveDraft) }
        await pause.waitUntilPaused()
        model.send(.sheetDismissed)
        model.send(.addItemTapped(.card))
        let replacement = try #require(model.state.sheet?.draft)
        pause.resume(); await save.value
        #expect(model.state.sheet?.draft == replacement)
    }

    @Test
    func permissionLossClosesEditorAndRejectsLateBindingUpdates() async throws {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()]))
        try await openEditor(model)
        let oldDraft = try #require(model.state.sheet?.draft)
        repository.syncOutput = vaultSnapshot(ciphers: [.fixture(reprompt: .password)], revision: 2)
        await model.perform(.loadVault)
        model.send(.draftChanged(oldDraft))
        await model.perform(.saveDraft)
        #expect(model.state.sheet == nil)
        #expect(repository.saved.isEmpty)
    }

    @Test
    func hiddenSecretsAndUnsupportedKindsNeverOpenEditorsOrDeletion() async {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture(reprompt: .password)]))
        model.send(.editItemTapped(CipherID(rawValue: "cipher-1")))
        model.send(.deleteItemTapped(CipherID(rawValue: "cipher-1")))
        model.send(.addItemTapped(.bankAccount))
        #expect(model.state.sheet == nil)
        #expect(model.state.pendingDeleteID == nil)
        #expect(repository.saved.isEmpty)
    }

    @Test
    func deleteRechecksPermissionsAndPublishesRepositorySnapshot() async {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()]))
        let id = CipherID(rawValue: "cipher-1")
        model.send(.deleteItemTapped(id))
        model.state.snapshot = vaultSnapshot(
            ciphers: [.fixture(permissions: .init(delete: false, restore: false))],
            revision: 2
        )
        await model.perform(.confirmDelete)
        #expect(repository.deleted.isEmpty)
        model.state.snapshot = repository.snapshot
        model.send(.deleteItemTapped(id))
        await model.perform(.confirmDelete)
        #expect(repository.deleted.map(\.id) == [id])
        #expect(model.state.visibleItems.isEmpty)
        #expect(model.state.pendingDeleteID == nil)
    }

    @Test
    func failedAndCancelledSyncKeepContentAndWarnings() async {
        let initial = vaultSnapshot(ciphers: [.fixture()], warnings: [.unavailableItems(count: 2)])
        let (model, repository) = make(initial)
        repository.syncError = ProcessorFixtureError.secretDiagnostic
        await model.perform(.loadVault)
        #expect(model.state.snapshot.items == initial.items)
        #expect(model.state.unavailableItemCount == 2)
        #expect(model.state.errorMessage == "Couldn't sync your vault. Please try again.")
        repository.syncError = CancellationError()
        await model.perform(.loadVault)
        #expect(model.state.errorMessage == nil)
        #expect(!model.state.isLoading)
    }

    @Test
    func successfulSyncReplacesTheIncompleteWarning() async {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()], warnings: [.unavailableItems(count: 2)]))
        repository.syncOutput = vaultSnapshot(ciphers: [.fixture(name: "Recovered")], revision: 2)
        await model.perform(.loadVault)
        #expect(model.state.visibleItems.map(\.name) == ["Recovered"])
        #expect(model.state.loadWarnings.isEmpty)
    }

    @Test
    func generatorChangesInvalidateOutputAndValidationErrorsStaySafe() async {
        let (model, _) = make()
        model.state.generatedPassword = "old"
        model.send(
            .generatorOptionsChanged(
                .init(useUppercase: false, useLowercase: false, useNumbers: false, useSpecial: false)
            )
        )
        #expect(model.state.generatedPassword.isEmpty)
        await model.perform(.regeneratePassword)
        #expect(model.state.generatorErrorMessage == "Select at least one character type.")
        model.send(.generatorOptionsChanged(.init()))
        await model.perform(.regeneratePassword)
        #expect(model.state.generatedPassword == "generated-password")
    }

    @Test
    func revisionAndSelectionChangesRejectLateTotpAndPasskeyResults() async throws {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()]))
        model.send(.itemSelected(CipherID(rawValue: "cipher-1")))
        let context = try #require(model.state.selectedItem?.context)
        let pause = ProcessorPause()
        repository.beforeDetail = { await pause.pause() }
        let totp = Task { await model.perform(.refreshTotp(context)) }
        await pause.waitUntilPaused()
        model.send(.searchQueryChanged("not-found"))
        pause.resume(); await totp.value
        #expect(model.state.oneTimeCode == nil)
        #expect(model.state.selectedItemID == nil)
        await model.perform(.loadPasskeys(context))
        #expect(repository.passkeyCalls == 0)
    }

    @Test
    func runtimeRevocationRejectsALateSyncAndClearsUISecrets() async {
        let gate = ProcessorAccessGate()
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()]), gate: gate)
        repository.beforeSync = { gate.revoke() }
        await model.perform(.loadVault)
        #expect(model.state.snapshot.items.isEmpty)
        #expect(model.state.sheet == nil)
        #expect(model.state.selectedItemID == nil)
        #expect(!model.state.isLoading)
    }

    @Test
    func cancellingADetailConsumerDoesNotClearTheWholeScreen() async {
        let (model, _) = make(vaultSnapshot(ciphers: [.fixture()]))
        let pause = ProcessorPause()
        let task = Task { await pause.pause(); await model.perform(.loadVault) }
        await pause.waitUntilPaused()
        task.cancel(); pause.resume(); await task.value
        #expect(model.state.visibleItems.count == 1)
    }

    @Test
    func attachmentConfirmationCannotRetargetAfterNavigationOrPermissionLoss() async {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture(), .fixture(id: "cipher-2")]))
        model.send(.itemSelected(CipherID(rawValue: "cipher-1")))
        model.state.pendingAttachmentDelete = attachmentReference()
        model.send(.itemSelected(CipherID(rawValue: "cipher-2")))
        await model.perform(.confirmDeleteAttachment)
        #expect(repository.attachmentDeletes.isEmpty)
        #expect(model.state.pendingAttachmentDelete == nil)
        // A retained system confirmation callback must also be dismissed, not left hanging.
        model.state.pendingAttachmentDelete = attachmentReference()
        await model.perform(.confirmDeleteAttachment)
        #expect(repository.attachmentDeletes.isEmpty)
        #expect(model.state.pendingAttachmentDelete == nil)
    }

    @Test
    func confirmedAttachmentCleanupFailureDoesNotRecommendRepeatingUpload() async {
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()]))
        repository.attachmentError = VaultRepositoryError.committedButCleanupFailed
        await model.perform(.pickAttachment(cipherID: CipherID(rawValue: "cipher-1")))
        #expect(model.state.errorMessage?.contains("Don't repeat the upload") == true)
        #expect(model.state.errorMessage?.contains("Lock the vault") == true)
        #expect(!model.state.isAttachmentBusy)
    }

    @Test(arguments: [false, true])
    func cancelledOrFailedPickerNeverSubmitsAnUpload(_ fails: Bool) async {
        let picker = MockFileImportClient()
        if fails { picker.errorToThrow = ProcessorFixtureError.secretDiagnostic }
        let (model, repository) = make(vaultSnapshot(ciphers: [.fixture()]), fileImportClient: picker)
        await model.perform(.pickAttachment(cipherID: CipherID(rawValue: "cipher-1")))
        #expect(repository.attachmentUploads.isEmpty)
        #expect(!model.state.isAttachmentBusy)
        if fails {
            #expect(model.state.errorMessage != nil)
            #expect(model.state.errorMessage?.contains("secretDiagnostic") == false)
        } else { #expect(model.state.errorMessage == nil) }
    }

    @Test(arguments: [false, true])
    func protectedAttachmentActionsNeverReachTheRepository(_ reprompt: Bool) async {
        let (model, repository) = make(vaultSnapshot(ciphers: [
            .fixture(viewPassword: reprompt, reprompt: reprompt ? .password : .none),
        ]))
        model.send(.itemSelected(CipherID(rawValue: "cipher-1")))
        await model.perform(.pickAttachment(cipherID: CipherID(rawValue: "cipher-1")))
        await model.perform(.downloadAttachment(attachmentReference()))
        model.state.pendingAttachmentDelete = attachmentReference()
        await model.perform(.confirmDeleteAttachment)
        #expect(repository.attachmentUploads.isEmpty)
        #expect(repository.attachmentDownloads.isEmpty)
        #expect(repository.attachmentDeletes.isEmpty)
        #expect(model.state.pendingAttachmentDelete == nil)
        #expect(model.state.previewURL == nil)
    }

    @Test
    func attachmentDeletionRequiresACurrentUniqueReferenceAndCanBeCancelled() async {
        let attachment = VaultAttachmentReference(
            cipherID: CipherID(rawValue: "cipher-1"),
            attachmentID: AttachmentID(rawValue: "attachment-1")
        )
        let initial = vaultSnapshot(ciphers: [.fixture(attachments: [
            .init(id: "attachment-1", url: nil, size: nil, sizeName: nil, fileName: "name", key: nil),
        ])])
        let (model, repository) = make(initial)
        model.send(.itemSelected(attachment.cipherID))
        model.send(.deleteAttachmentTapped(attachment))
        #expect(model.state.pendingAttachmentDelete == attachment)
        model.send(.deleteAttachmentCancelled)
        await model.perform(.confirmDeleteAttachment)
        #expect(repository.attachmentDeletes.isEmpty)
        model.send(.deleteAttachmentTapped(attachment))
        model.state.snapshot = vaultSnapshot(ciphers: [.fixture(edit: false)], revision: 2)
        await model.perform(.confirmDeleteAttachment)
        #expect(repository.attachmentDeletes.isEmpty)
        #expect(model.state.pendingAttachmentDelete == nil)
        model.state.snapshot = initial
        model.send(.deleteAttachmentTapped(attachment))
        await model.perform(.confirmDeleteAttachment)
        #expect(repository.attachmentDeletes == [attachment])
        #expect(model.state.pendingAttachmentDelete == nil)
        #expect(!model.state.isAttachmentBusy)
    }

    @Test
    func unexpectedGeneratorFailureClearsOldOutputWithoutLeakingDiagnostics() async {
        let (model, _) = make(generator: FailingProcessorGenerator())
        model.state.generatedPassword = "previous-secret"
        await model.perform(.regeneratePassword)
        #expect(model.state.generatedPassword.isEmpty)
        #expect(model.state.generatorErrorMessage == "Couldn't generate a password. Please try again.")
    }
}

private final class ObservationChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var didChange: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private enum ProcessorFixtureError: Error { case secretDiagnostic }

private struct ProcessorGenerator: PasswordGenerating {
    func generatePassword(options: PasswordGeneratorOptions) throws -> String {
        try options.validate(); return "generated-password"
    }
}

private struct FailingProcessorGenerator: PasswordGenerating {
    func generatePassword(options: PasswordGeneratorOptions) throws -> String {
        throw ProcessorFixtureError.secretDiagnostic
    }
}

private final class ProcessorAccessGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    func check() throws { try Task.checkCancellation(); guard lock.withLock({ active }) else { throw CancellationError() } }
    func revoke() { lock.withLock { active = false } }
}

@MainActor
private final class ProcessorPause {
    private var paused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        paused = true; pauseWaiters.forEach { $0.resume() }; pauseWaiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilPaused() async {
        if !paused { await withCheckedContinuation { pauseWaiters.append($0) } }
    }

    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class ProcessorRepository: VaultRepository {
    var recoveryReview: PasskeyRegistrationRecoveryReview?
    var recoveryError: Error?
    var beforeRecoveryReview: (() async -> Void)?
    var beforeRecoveryAcknowledgment: (() async -> Void)?
    var recoveryAcknowledgments: [PasskeyRegistrationRecoveryReview] = []
    func preparePasskeyRegistrationRecoveryReview() async throws -> PasskeyRegistrationRecoveryReview {
        await beforeRecoveryReview?()
        if let recoveryError { throw recoveryError }
        guard let recoveryReview else { throw PasskeyRegistrationReviewError.unavailable }
        return recoveryReview
    }

    func abandonPasskeyRegistrationRecovery(_ review: PasskeyRegistrationRecoveryReview) async throws {
        recoveryAcknowledgments.append(review)
        await beforeRecoveryAcknowledgment?()
        if let recoveryError { throw recoveryError }
        snapshot = VaultSnapshot(
            revision: snapshot.revision,
            items: snapshot.items,
            lastSuccessfulSync: snapshot.lastSuccessfulSync,
            isStale: snapshot.isStale,
            warnings: snapshot.warnings.filter { $0 != .passkeyRegistrationRecoveryPending },
            projectionStatus: snapshot.projectionStatus
        )
    }

    var snapshot: VaultSnapshot
    var syncOutput: VaultSnapshot?
    var syncError: Error?
    var saveError: Error?
    var attachmentError: Error?
    var downloadURL: URL?
    var beforeSave: (() async -> Void)?
    var beforeSync: (() async -> Void)?
    var beforeDetail: (() async -> Void)?
    var saved: [VaultItemDraft] = []
    var deleted: [VaultItemContext] = []
    var attachmentDeletes: [VaultAttachmentReference] = []
    var attachmentUploads: [VaultItemContext] = []
    var attachmentDownloads: [VaultAttachmentReference] = []
    var passkeyCalls = 0
    init(snapshot: VaultSnapshot) { self.snapshot = snapshot }
    func observeVault() -> AsyncStream<VaultSnapshot> { AsyncStream { $0.yield(snapshot); $0.finish() } }
    func currentSnapshot() -> VaultSnapshot { snapshot }
    func sync() async throws {
        await beforeSync?(); if let syncError { throw syncError }; if let syncOutput { snapshot = syncOutput }
    }

    func makeDraft(for id: CipherID) throws -> VaultItemDraft {
        guard let detail = snapshot.details[id], detail.permissions.canEdit else { throw VaultRepositoryError.readOnly }
        var draft = VaultItemDraft(editingID: id, kind: detail.kind, baseRevision: detail.context.revision)
        draft.name = detail.name; return draft
    }

    func save(_ draft: VaultItemDraft) async throws -> CipherID {
        saved.append(draft); await beforeSave?(); if let saveError { throw saveError }
        let id = draft.editingID ?? CipherID(rawValue: "created")
        snapshot = vaultSnapshot(ciphers: [.fixture(id: id.rawValue, name: draft.name)], revision: snapshot.revision + 1)
        return id
    }

    func delete(_ context: VaultItemContext) {
        deleted.append(context); snapshot = vaultSnapshot(revision: snapshot.revision + 1)
    }

    func oneTimeCode(for context: VaultItemContext) async -> VaultOneTimeCode {
        await beforeDetail?(); return VaultOneTimeCode(context: context, code: "123456", period: 30)
    }

    func passkeys(for context: VaultItemContext) -> [VaultPasskeySummary] { passkeyCalls += 1; return [] }
    func uploadAttachment(to context: VaultItemContext, file: any ImportedFile) throws {
        attachmentUploads.append(context)
        if let attachmentError { throw attachmentError }
    }

    func downloadAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws -> URL {
        attachmentDownloads.append(reference)
        await beforeDetail?()
        guard let downloadURL else { throw VaultRepositoryError.missingItem }
        return downloadURL
    }

    func deleteAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) { attachmentDeletes.append(
        reference
    ) }
    func lock() { snapshot = vaultSnapshot(revision: snapshot.revision + 1) }
}
