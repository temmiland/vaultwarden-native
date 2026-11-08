import AutoFillContract
import Data
import Domain
import Foundation
import Testing

@Suite
struct VaultMutationPipelineTests {
    @Test
    func disabledProviderKeepsTheCurrentCacheWithoutFalselyCompletingRegistrationRecovery() async throws {
        let source = MutationSource(), files = MutationFiles(), identities = MutationIdentities()
        await identities.setEnabled(false)
        let recovery = PipelineRecoveryFixture(files: files, identities: identities)
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: files),
            identityPublisher: CredentialIdentityPublisher(
                store: identities, identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in }, checkClearAccess: {}
            ),
            registrationRecovery: recovery
        )
        try await repository.sync()
        let disabled = await repository.currentSnapshot()
        #expect(disabled.projectionStatus == .suggestionsDisabled(revision: disabled.revision))
        #expect(!disabled.isStale)
        #expect(disabled.lastSuccessfulSync != nil)
        #expect(files.bytes != nil)
        #expect(await recovery.canResolveCalls == [false])
        await identities.setEnabled(true)
        try await repository.sync()
        let enabled = await repository.currentSnapshot()
        #expect(enabled.projectionStatus == .current(revision: enabled.revision))
        #expect(await recovery.canResolveCalls == [false, true])
        #expect(await source.writeCount == 0)
    }

    @Test
    func alreadyCancelledAcknowledgmentCannotRemoveTracking() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let repository = DefaultVaultRepository(
            source: MutationSource(),
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: MutationFiles()),
            identityPublisher: CredentialIdentityPublisher(
                store: MutationIdentities(),
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: fixture.recovery()
        )
        try await repository.sync()
        let review = try await repository.preparePasskeyRegistrationRecoveryReview(), gate = AuthOperationTestGate()
        let task = Task { await gate.pause(); try await repository.abandonPasskeyRegistrationRecovery(review) }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.journal.records(requiring: fixture.fresh).count == 1)
        #expect(await repository.currentSnapshot().warnings.contains(.passkeyRegistrationRecoveryPending))
    }

    @Test
    func explicitRecoveryAcknowledgmentUpdatesWarningWithoutAnyServerWrite() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let source = MutationSource(), files = MutationFiles(), identities = MutationIdentities()
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: files),
            identityPublisher: CredentialIdentityPublisher(
                store: identities,
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: fixture.recovery()
        )
        try await repository.sync()
        #expect(await repository.currentSnapshot().warnings.contains(.passkeyRegistrationRecoveryPending))
        let review = try await repository.preparePasskeyRegistrationRecoveryReview()
        #expect(try fixture.journal.records(requiring: fixture.fresh).count == 1)
        try await repository.abandonPasskeyRegistrationRecovery(review)
        #expect(await repository.currentSnapshot().warnings.isEmpty)
        #expect(await repository.currentSnapshot().revision == review.vaultRevision)
        #expect(await source.writeCount == 0)
        #expect(await source.events == ["fetch"])
        await #expect(throws: PasskeyRegistrationReviewError.syncRequired) {
            try await repository.abandonPasskeyRegistrationRecovery(review)
        }
    }

    @Test(arguments: ["no-sync", "cache", "identities", "partial", "mutation", "failed-sync"])
    func reviewRequiresFreshCompleteSyncWithCurrentCacheAndOSProjection(_ reason: String) async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let source = MutationSource(), files = MutationFiles(), identities = MutationIdentities()
        if reason == "cache" { files.failWrites = true }
        if reason == "identities" { await identities.failNextReplacement() }
        if reason == "partial" { await source.setWarnings([.unavailableItems(count: 1)]) }
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: files),
            identityPublisher: CredentialIdentityPublisher(
                store: identities,
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: fixture.recovery()
        )
        if reason != "no-sync" { try await repository.sync() }
        if reason == "mutation" { _ = try await repository.save(.init(kind: .login)) }
        if reason == "failed-sync" {
            await source.failNextOutput()
            await #expect(throws: (any Error).self) { try await repository.sync() }
        }
        await #expect(throws: PasskeyRegistrationReviewError.syncRequired) { try await repository.preparePasskeyRegistrationRecoveryReview(
        ) }
        #expect(try fixture.journal.records(requiring: fixture.fresh).count == 1)
    }

    @Test
    func syncInvalidatesConsentEvenWhenTheMarkerDidNotChange() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let repository = DefaultVaultRepository(
            source: MutationSource(),
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: MutationFiles()),
            identityPublisher: CredentialIdentityPublisher(
                store: MutationIdentities(),
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: fixture.recovery()
        )
        try await repository.sync()
        let old = try await repository.preparePasskeyRegistrationRecoveryReview()
        try await repository.sync()
        await #expect(throws: PasskeyRegistrationReviewError.reviewChanged) { try await repository.abandonPasskeyRegistrationRecovery(
            old
        ) }
        #expect(try fixture.journal.records(requiring: fixture.fresh).count == 1)
        await #expect(throws: PasskeyRegistrationReviewError.syncRequired) { try await repository.preparePasskeyRegistrationRecoveryReview(
        ) }
        try await repository.sync()
        let current = try await repository.preparePasskeyRegistrationRecoveryReview()
        try await repository.abandonPasskeyRegistrationRecovery(current)
        #expect(await repository.currentSnapshot().warnings.isEmpty)
    }

    @Test
    func cancelledConsumerDoesNotSkipAnExplicitlyCommittedLocalAcknowledgment() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let gate = AuthOperationTestGate(), source = MutationSource()
        let recovery = GatedRecoveryReview(delegate: fixture.recovery(), gate: gate)
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: MutationFiles()),
            identityPublisher: CredentialIdentityPublisher(
                store: MutationIdentities(),
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: recovery
        )
        try await repository.sync()
        let review = try await repository.preparePasskeyRegistrationRecoveryReview()
        let task = Task { try await repository.abandonPasskeyRegistrationRecovery(review) }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        try await task.value
        #expect(await repository.currentSnapshot().warnings.isEmpty)
        #expect(try fixture.journal.records(requiring: fixture.fresh).isEmpty)
        #expect(await source.writeCount == 0)
    }

    @Test
    func lockDuringAcknowledgmentCannotPublishALateWarningOrSnapshot() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let gate = AuthOperationTestGate(), source = MutationSource()
        let recovery = GatedRecoveryReview(delegate: fixture.recovery(), gate: gate)
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: MutationFiles()),
            identityPublisher: CredentialIdentityPublisher(
                store: MutationIdentities(),
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: recovery
        )
        try await repository.sync()
        let review = try await repository.preparePasskeyRegistrationRecoveryReview()
        let task = Task { try await repository.abandonPasskeyRegistrationRecovery(review) }
        await gate.waitUntilPaused(); await repository.lock(); await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await repository.currentSnapshot().items.isEmpty)
        #expect(await repository.currentSnapshot().warnings.isEmpty)
        #expect(await source.writeCount == 0)
    }

    private func make(
        _ source: MutationSource,
        files: MutationFiles = MutationFiles(),
        identities: MutationIdentities = MutationIdentities()
    )
        -> (DefaultVaultRepository, MutationFiles, MutationIdentities) {
        (
            DefaultVaultRepository(
                source: source,
                projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: files),
                identityPublisher: CredentialIdentityPublisher(
                    store: identities,
                    identityMutations: IdentityMutationTestCoordinator(),
                    checkProjection: { _ in },
                    checkClearAccess: {}
                )
            ),
            files,
            identities
        )
    }

    @Test
    func cancelledUIConsumerCannotSkipAnAcknowledgedMutationProjection() async throws {
        let source = MutationSource(); let (repository, files, identities) = make(source)
        try await repository.sync()
        await source.pauseNextSave()
        let save = Task { try await repository.save(VaultItemDraft(kind: .login)) }
        await source.waitUntilSaveStarted()
        save.cancel(); await source.resumeSave()
        #expect(try await save.value == CipherID(rawValue: "created"))
        let snapshot = await repository.currentSnapshot()
        let cache = try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: #require(files.bytes))
        #expect(snapshot.revision == 2)
        #expect(cache.revision == snapshot.revision)
        #expect(await identities.lastRevision == snapshot.revision)
        #expect(snapshot.projectionStatus == .current(revision: snapshot.revision))
    }

    @Test
    func acknowledgedWriteWithOutputFailureInvalidatesCacheAndIdentities() async throws {
        let source = MutationSource(); let (repository, files, identities) = make(source)
        try await repository.sync()
        await source.failNextOutput()
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) {
            _ = try await repository.save(VaultItemDraft(kind: .login))
        }
        #expect(files.bytes == nil)
        #expect(await identities.lastRevision == nil)
        #expect(await repository.currentSnapshot().isStale)
        #expect(await repository.currentSnapshot().projectionStatus == .unavailable)
        #expect(await source.writeCount == 1)
    }

    @Test
    func projectionWriteFailureDoesNotUndoServerSuccessOrOfferADuplicateWrite() async throws {
        let source = MutationSource(); let (repository, files, identities) = make(source)
        try await repository.sync()
        files.failWrites = true
        #expect(try await repository.save(.init(kind: .login)) == CipherID(rawValue: "created"))
        #expect(await source.writeCount == 1)
        #expect(await repository.currentSnapshot().revision == 2)
        #expect(await repository.currentSnapshot().projectionStatus == .unavailable)
        #expect(files.bytes == nil)
        #expect(await identities.lastRevision == nil)
        files.failWrites = false
        try await repository.sync()
        #expect(await repository.currentSnapshot().projectionStatus == .current(revision: 3))
    }

    @Test
    func lockDuringAServerMutationDeniesLateSnapshotAndCachePublication() async throws {
        let source = MutationSource(); let (repository, files, identities) = make(source)
        try await repository.sync()
        await source.pauseNextSave()
        let save = Task { try await repository.save(.init(kind: .login)) }
        await source.waitUntilSaveStarted()
        await repository.lock()
        await source.resumeSave()
        await #expect(throws: CancellationError.self) { _ = try await save.value }
        #expect(await repository.currentSnapshot().items.isEmpty)
        #expect(files.bytes == nil)
        #expect(await identities.lastRevision == nil)
        await #expect(throws: CancellationError.self) { try await repository.sync() }
    }

    @Test
    func queuedSaveCannotPassAnActiveSync() async throws {
        let source = MutationSource(); let (repository, _, _) = make(source)
        await source.pauseNextFetch()
        let sync = Task { try await repository.sync() }
        await source.waitUntilFetchStarted()
        let save = Task { try await repository.save(.init(kind: .login)) }
        #expect(await source.events == ["fetch"])
        await source.resumeFetch()
        try await sync.value; _ = try await save.value
        #expect(await source.events == ["fetch", "save"])
    }

    @Test
    func recoveryIsAttemptedOnlyAfterMatchingCacheAndIdentityPublication() async throws {
        let source = MutationSource(), files = MutationFiles(), identities = MutationIdentities()
        let recovery = PipelineRecoveryFixture(files: files, identities: identities)
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: files),
            identityPublisher: CredentialIdentityPublisher(
                store: identities,
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: recovery
        )
        try await repository.sync()
        #expect(await recovery.canResolveCalls == [true])
        #expect(await repository.currentSnapshot().warnings.isEmpty)
        #expect(await source.writeCount == 0)
    }

    @Test(arguments: ["cache", "identities", "no-writer"])
    func failedProjectionCannotClearRecoveryAndSuccessfulSyncRepairsIt(_ failure: String) async throws {
        let source = MutationSource(), files = MutationFiles(), identities = MutationIdentities()
        if failure == "cache" { files.failWrites = true }
        if failure == "identities" { await identities.failNextReplacement() }
        let recovery = PipelineRecoveryFixture(files: files, identities: identities)
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: failure == "no-writer" ? nil : AutoFillProjectionWriter(
                accountID: "user",
                fileStore: files
            ),
            identityPublisher: CredentialIdentityPublisher(
                store: identities,
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: recovery
        )
        try await repository.sync()
        #expect(await recovery.canResolveCalls == [false])
        #expect(await repository.currentSnapshot().warnings.contains(.passkeyRegistrationRecoveryPending))
        files.failWrites = false
        try await repository.sync()
        #expect(await recovery.canResolveCalls == [false, failure != "no-writer"])
        #expect(
            await repository.currentSnapshot().warnings.contains(.passkeyRegistrationRecoveryPending) == (
                failure == "no-writer"
            )
        )
        #expect(await source.writeCount == 0)
    }

    @Test
    func recoveryStorageFailureIsVisibleAndAnOrdinaryMutationCannotClearItsWarning() async throws {
        let source = MutationSource(), files = MutationFiles(), identities = MutationIdentities()
        let recovery = PipelineRecoveryFixture(files: files, identities: identities)
        await recovery.fail()
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: files),
            identityPublisher: CredentialIdentityPublisher(
                store: identities,
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: recovery
        )
        try await repository.sync()
        #expect(await repository.currentSnapshot().warnings.contains(.passkeyRegistrationRecoveryPending))
        _ = try await repository.save(VaultItemDraft(kind: .login))
        #expect(await recovery.canResolveCalls.count == 1)
        #expect(await repository.currentSnapshot().warnings.contains(.passkeyRegistrationRecoveryPending))
        await recovery.repair(); try await repository.sync()
        #expect(await repository.currentSnapshot().warnings.isEmpty)
        #expect(await source.writeCount == 1)
    }

    @Test
    func lockDuringRecoveryCannotPublishALateSnapshot() async throws {
        let source = MutationSource(), files = MutationFiles(), identities = MutationIdentities()
        let gate = AuthOperationTestGate(), recovery = PipelineRecoveryFixture(files: files, identities: identities)
        await recovery.pause(gate)
        let repository = DefaultVaultRepository(
            source: source,
            projectionWriter: AutoFillProjectionWriter(accountID: "user", fileStore: files),
            identityPublisher: CredentialIdentityPublisher(
                store: identities,
                identityMutations: IdentityMutationTestCoordinator(),
                checkProjection: { _ in },
                checkClearAccess: {}
            ),
            registrationRecovery: recovery
        )
        let task = Task { try await repository.sync() }
        await gate.waitUntilPaused(); await repository.lock(); await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        let snapshot = await repository.currentSnapshot()
        let identityRevision = await identities.lastRevision
        #expect(snapshot.items.isEmpty && snapshot.warnings.isEmpty)
        #expect(files.bytes == nil && identityRevision == nil)
    }
}

private actor GatedRecoveryReview: VaultRegistrationRecovery {
    let delegate: PasskeyRegistrationRecoveryReconciler
    let gate: AuthOperationTestGate
    init(delegate: PasskeyRegistrationRecoveryReconciler, gate: AuthOperationTestGate) { self.delegate = delegate; self.gate = gate }
    func reconcile(identities: [CredentialIdentityDescriptor], canResolve: Bool) async throws -> Bool {
        try await delegate.reconcile(identities: identities, canResolve: canResolve)
    }

    func prepareReview(vaultRevision: UInt64) async throws -> PasskeyRegistrationRecoveryReview {
        try await delegate.prepareReview(vaultRevision: vaultRevision)
    }

    func abandon(_ review: PasskeyRegistrationRecoveryReview) async throws -> Bool {
        let remaining = try await delegate.abandon(review)
        await gate.pause() // deliberately noncooperative after the actual local write
        return remaining
    }
}

private actor PipelineRecoveryFixture: VaultRegistrationRecovery {
    let files: MutationFiles
    let identities: MutationIdentities
    private var failing = false
    private var gate: AuthOperationTestGate?
    private(set) var canResolveCalls: [Bool] = []
    init(files: MutationFiles, identities: MutationIdentities) { self.files = files; self.identities = identities }
    func fail() { failing = true }
    func repair() { failing = false }
    func pause(_ value: AuthOperationTestGate) { gate = value }
    func reconcile(identities _: [CredentialIdentityDescriptor], canResolve: Bool) async throws -> Bool {
        canResolveCalls.append(canResolve)
        if canResolve {
            let cache = try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: #require(files.bytes))
            #expect(await identities.lastRevision == cache.revision)
        }
        await gate?.pause()
        if failing { throw PasskeyRecoveryFixtureError.storage }
        return !canResolve
    }
}

private enum MutationFixtureError: Error { case output, write }

private final class MutationFiles: AutoFillProjectionFileStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Foundation.Data?
    private var writeFailure = false
    var bytes: Foundation.Data? { lock.withLock { storage } }
    var failWrites: Bool { get { lock.withLock { writeFailure } } set { lock.withLock { writeFailure = newValue } } }
    func readProjection() throws -> Foundation.Data? { bytes }
    func replaceProjectionAtomically(with data: Foundation.Data) throws {
        try lock.withLock { if writeFailure { throw MutationFixtureError.write }; storage = data }
    }

    func removeProjection() throws { lock.withLock { storage = nil } }
}

private actor MutationIdentities: CredentialIdentityPublishing {
    private(set) var lastRevision: UInt64?
    private var failReplacement = false
    private var isEnabled = true
    func setEnabled(_ value: Bool) { isEnabled = value }
    func failNextReplacement() { failReplacement = true }
    func replaceCredentialIdentities(_ identities: [CredentialIdentityDescriptor], revision: UInt64) throws {
        guard isEnabled else { throw CredentialIdentityPublishingError.disabled }
        if failReplacement { failReplacement = false; throw MutationFixtureError.write }
        lastRevision = revision
    }

    func removeAllCredentialIdentities() throws {
        guard isEnabled else { throw CredentialIdentityPublishingError.disabled }
        lastRevision = nil
    }
}

private actor MutationSource: VaultSessionSource {
    private var revision: UInt64 = 0
    private var shouldPauseSave = false
    private var shouldPauseFetch = false
    private var failOutput = false
    private var warnings: [VaultLoadWarning] = []
    func setWarnings(_ value: [VaultLoadWarning]) { warnings = value }
    private var saveStarted = false
    private var fetchStarted = false
    private var saveWaiters: [CheckedContinuation<Void, Never>] = []
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private(set) var writeCount = 0
    private(set) var events: [String] = []
    func pauseNextSave() { shouldPauseSave = true }
    func pauseNextFetch() { shouldPauseFetch = true }
    func failNextOutput() { failOutput = true }
    func waitUntilSaveStarted() async { if !saveStarted { await withCheckedContinuation { saveWaiters.append($0) } } }
    func waitUntilFetchStarted() async { if !fetchStarted { await withCheckedContinuation { fetchWaiters.append($0) } } }
    func resumeSave() { saveContinuation?.resume(); saveContinuation = nil }
    func resumeFetch() { fetchContinuation?.resume(); fetchContinuation = nil }
    func fetchOutput() async throws -> VaultSourceOutput {
        events.append("fetch"); fetchStarted = true; fetchWaiters.forEach { $0.resume() }; fetchWaiters.removeAll()
        if shouldPauseFetch { shouldPauseFetch = false; await withCheckedContinuation { fetchContinuation = $0 } }
        revision += 1; return try currentOutput()
    }

    func currentOutput() throws -> VaultSourceOutput {
        if failOutput { failOutput = false; throw MutationFixtureError.output }
        let item = VaultItemSummary(
            id: CipherID(rawValue: "created"),
            kind: .login,
            name: "Name",
            subtitle: nil,
            isFavorite: false,
            isEditable: true
        )
        return VaultSourceOutput(
            snapshot: VaultSnapshot(
                revision: revision,
                items: [item],
                lastSuccessfulSync: nil,
                isStale: false,
                warnings: warnings
            ),
            encryptedLoginRecords: [
                EncryptedLoginRecord(
                    id: "created",
                    deletedAt: nil,
                    encryptedCipherPayload: Foundation.Data("ciphertext".utf8)
                ),
            ],
            encryptedOrganizationKeys: [:],
            identitySources: []
        )
    }

    func save(_ draft: VaultItemDraft) async -> CipherID {
        events.append("save"); writeCount += 1; saveStarted = true
        saveWaiters.forEach { $0.resume() }; saveWaiters.removeAll()
        if shouldPauseSave { shouldPauseSave = false; await withCheckedContinuation { saveContinuation = $0 } }
        revision += 1; return CipherID(rawValue: "created")
    }

    func makeDraft(for id: CipherID) throws -> VaultItemDraft { throw VaultRepositoryError.unsupportedOperation }
    func delete(_ context: VaultItemContext) throws { throw VaultRepositoryError.unsupportedOperation }
    func oneTimeCode(for context: VaultItemContext) throws -> VaultOneTimeCode { throw VaultRepositoryError.unsupportedOperation }
    func passkeys(for context: VaultItemContext) throws -> [VaultPasskeySummary] { throw VaultRepositoryError.unsupportedOperation }
    func uploadAttachment(to context: VaultItemContext, file: any ImportedFile, encryptedURL: URL) throws { throw VaultRepositoryError.unsupportedOperation }
    func downloadAttachment(
        _ reference: VaultAttachmentReference,
        context: VaultItemContext,
        encryptedURL: URL,
        decryptedURL: URL
    ) throws { throw VaultRepositoryError.unsupportedOperation }
    func deleteAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) throws { throw VaultRepositoryError.unsupportedOperation }
    func revoke() {}
}
