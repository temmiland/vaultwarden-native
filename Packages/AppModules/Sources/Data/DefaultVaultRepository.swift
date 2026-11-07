import AutoFillContract
import Domain
import Foundation
import SecurityStorage

public protocol VaultSnapshotSource: Sendable {
    func fetchVaultSnapshot() async throws -> VaultSnapshot
}

/// One authority per unlocked session. Source operations are FIFO, shared sync is single-flight,
/// and UI/cache/system identities are projections of the same committed source revision.
public actor DefaultVaultRepository: VaultRepository {
    private let source: any VaultSnapshotSource
    private let projectionWriter: AutoFillProjectionWriter?
    private let identityPublisher: CredentialIdentityPublisher?
    private let registrationRecovery: (any VaultRegistrationRecovery)?
    private let temporaryFiles: SensitiveTemporaryFileStore
    private let now: @Sendable () -> Date
    private var snapshot: VaultSnapshot
    private var isClosed = false
    private var closingTask: Task<Void, Never>?
    private var inFlightSync: (id: UUID, task: Task<Void, Error>)?
    private var syncConsumers = 0

    // Read-only module-internal diagnostic lets gated tests prove both consumers actually joined
    // the blocked sync before completion. Spawning a Task or yielding is not such a barrier.
    var activeSyncConsumerCount: Int { syncConsumers }
    private var operationActive = false
    private var recoverySyncRevision: UInt64?
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [UUID: AsyncStream<VaultSnapshot>.Continuation] = [:]

    public init(
        source: any VaultSnapshotSource,
        initialSnapshot: VaultSnapshot = VaultSnapshot(revision: 0, items: [], lastSuccessfulSync: nil, isStale: false),
        projectionWriter: AutoFillProjectionWriter? = nil,
        identityPublisher: CredentialIdentityPublisher? = nil,
        registrationRecovery: (any VaultRegistrationRecovery)? = nil,
        temporaryFiles: SensitiveTemporaryFileStore = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source; snapshot = initialSnapshot; self.now = now
        self.projectionWriter = projectionWriter; self.identityPublisher = identityPublisher
        self.registrationRecovery = registrationRecovery
        self.temporaryFiles = temporaryFiles
    }

    public func observeVault() -> AsyncStream<VaultSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        }
    }

    public func currentSnapshot() -> VaultSnapshot { snapshot }

    public func sync() async throws {
        try checkOpen()
        let job: (id: UUID, task: Task<Void, Error>)
        if let inFlightSync { job = inFlightSync }
        else {
            let id = UUID()
            let task = Task { try await self.performSync() }
            job = (id, task); inFlightSync = job
        }
        syncConsumers += 1
        defer { syncConsumers -= 1 }
        do {
            try await job.task.value
            if inFlightSync?.id == job.id { inFlightSync = nil }
            try checkOpen()
        } catch {
            if inFlightSync?.id == job.id { inFlightSync = nil }
            throw error
        }
    }

    private func performSync() async throws {
        await acquireOperation()
        defer { releaseOperation() }
        recoverySyncRevision = nil
        do {
            try checkOpen()
            if let sessionSource = source as? any VaultSessionSource {
                try await commit(try await sessionSource.fetchOutput(), isSync: true)
            } else {
                let fetched = try await source.fetchVaultSnapshot()
                try checkOpen()
                guard fetched.revision >= snapshot.revision else { return }
                if fetched.revision > snapshot.revision || snapshot.isStale || snapshot.lastSuccessfulSync == nil {
                    snapshot = copying(fetched, lastSync: now(), stale: false)
                    publish()
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard !isClosed else { throw CancellationError() }
            markStale()
            throw error
        }
    }

    public func makeDraft(for id: CipherID) async throws -> VaultItemDraft {
        try checkOpen()
        let draft = try await sessionSource().makeDraft(for: id)
        try checkOpen()
        return draft
    }

    public func save(_ draft: VaultItemDraft) async throws -> CipherID {
        try await mutate { try await $0.save(draft) }
    }

    public func delete(_ context: VaultItemContext) async throws {
        try await mutate { try await $0.delete(context) }
    }

    public func oneTimeCode(for context: VaultItemContext) async throws -> VaultOneTimeCode {
        try checkOpen()
        let value = try await sessionSource().oneTimeCode(for: context)
        try checkOpen()
        return value
    }

    public func passkeys(for context: VaultItemContext) async throws -> [VaultPasskeySummary] {
        try checkOpen()
        let value = try await sessionSource().passkeys(for: context)
        try checkOpen()
        return value
    }

    public func preparePasskeyRegistrationRecoveryReview() async throws -> PasskeyRegistrationRecoveryReview {
        await acquireOperation()
        defer { releaseOperation() }
        try requireRecoverySync()
        guard let registrationRecovery else { throw PasskeyRegistrationReviewError.unavailable }
        let review = try await registrationRecovery.prepareReview(vaultRevision: snapshot.revision)
        try requireRecoverySync()
        guard review.vaultRevision == snapshot.revision else { throw PasskeyRegistrationReviewError.reviewChanged }
        return review
    }

    public func abandonPasskeyRegistrationRecovery(_ review: PasskeyRegistrationRecoveryReview) async throws {
        try checkOpen()
        // Explicit consent submits a local mutation. Consumer cancellation cannot skip its
        // acknowledgment; lock still rejects publication. This never calls a server-write port.
        let task = Task { try await self.performRecoveryAbandonment(review) }
        try await task.value
        guard !isClosed else { throw CancellationError() }
    }

    private func performRecoveryAbandonment(_ review: PasskeyRegistrationRecoveryReview) async throws {
        await acquireOperation()
        defer { recoverySyncRevision = nil; releaseOperation() } // success/failure both require fresh sync/consent
        try requireRecoverySync()
        guard review.vaultRevision == snapshot.revision, let registrationRecovery else {
            throw PasskeyRegistrationReviewError.reviewChanged
        }
        let pending = try await registrationRecovery.abandon(review)
        try requireRecoverySync()
        var warnings = snapshot.warnings.filter { $0 != .passkeyRegistrationRecoveryPending }
        if pending { warnings.append(.passkeyRegistrationRecoveryPending) }
        snapshot = copying(snapshot, stale: snapshot.isStale, warnings: warnings)
        publish()
    }

    private func requireRecoverySync() throws {
        try checkOpen()
        guard recoverySyncRevision == snapshot.revision, !snapshot.isStale, snapshot.lastSuccessfulSync != nil,
              snapshot.projectionStatus == .current(revision: snapshot.revision),
              !snapshot.warnings.contains(
                  where: { if case let .unavailableItems(count) = $0 { return count > 0 }; return false }
              ) else {
            throw PasskeyRegistrationReviewError.syncRequired
        }
    }

    public func uploadAttachment(to context: VaultItemContext, file: any ImportedFile) async throws {
        try checkOpen()
        let directory = try await temporaryFiles.makeWorkDirectory()
        do {
            let encrypted = try await temporaryFiles.makeSensitiveFile(in: directory, suggestedName: "encrypted.data")
            try await mutate { try await $0.uploadAttachment(to: context, file: file, encryptedURL: encrypted) }
        } catch {
            do { try await temporaryFiles.removeWorkDirectory(directory) }
            catch { throw VaultRepositoryError.temporaryCleanupFailed }
            throw error
        }
        do { try await temporaryFiles.removeWorkDirectory(directory) }
        catch { throw VaultRepositoryError.committedButCleanupFailed }
    }

    public func downloadAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws -> URL {
        try checkOpen()
        let directory = try await temporaryFiles.makeWorkDirectory()
        do {
            let encrypted = try await temporaryFiles.makeSensitiveFile(in: directory, suggestedName: "encrypted.data")
            let name = snapshot.details[reference.cipherID]?.attachments.first { $0.reference == reference }?.fileName ?? "attachment"
            let decrypted = try await temporaryFiles.makeSensitiveFile(in: directory, suggestedName: name)
            try await sessionSource().downloadAttachment(
                reference,
                context: context,
                encryptedURL: encrypted,
                decryptedURL: decrypted
            )
            try checkOpen()
            try await temporaryFiles.protectFile(at: decrypted)
            try checkOpen()
            return decrypted
        } catch {
            do { try await temporaryFiles.removeWorkDirectory(directory) }
            catch { throw VaultRepositoryError.temporaryCleanupFailed }
            throw error
        }
    }

    public func deleteAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws {
        try await mutate { try await $0.deleteAttachment(reference, context: context) }
    }

    private func mutate<T: Sendable>(
        _ operation: @escaping @Sendable (any VaultSessionSource) async throws -> T
    ) async throws -> T {
        try checkOpen()
        // Once submitted, this operation belongs to the repository, not a disappearing view.
        // Caller cancellation must not skip projection after an acknowledged server write.
        // Runtime revocation still cancels its scoped transport and rejects late publication.
        let task = Task { try await self.performMutation(operation) }
        let result = try await task.value
        // Preserve an acknowledged result even if just the caller was cancelled. Otherwise a
        // create draft could remain retryable although its server/cache commit already finished.
        guard !isClosed else { throw CancellationError() }
        return result
    }

    private func performMutation<T: Sendable>(
        _ operation: @Sendable (any VaultSessionSource) async throws -> T
    ) async throws -> T {
        await acquireOperation()
        defer { releaseOperation() }
        try checkOpen()
        recoverySyncRevision = nil
        let source = try sessionSource()
        do {
            let result = try await operation(source)
            do {
                try checkOpen()
                try await commit(try await source.currentOutput(), isSync: false)
            } catch is CancellationError { throw CancellationError() }
            catch { throw VaultRepositoryError.committedButRefreshFailed }
            return result
        } catch VaultRepositoryError.committedButRefreshFailed {
            if !isClosed {
                markStale()
                await projectionWriter?.invalidate()
                _ = await identityPublisher?.clear()
                if !isClosed { snapshot = copying(snapshot, stale: true, projection: .unavailable); publish() }
            }
            throw VaultRepositoryError.committedButRefreshFailed
        }
    }

    public func lock() async {
        if let closingTask { await closingTask.value; return }
        guard !isClosed else { return }
        isClosed = true
        recoverySyncRevision = nil
        inFlightSync?.task.cancel(); inFlightSync = nil
        snapshot = VaultSnapshot(
            revision: snapshot.revision == .max ? .max : snapshot.revision + 1,
            items: [],
            lastSuccessfulSync: nil,
            isStale: false
        )
        publish()
        let closingTask = Task {
            await (source as? any VaultSessionSource)?.revoke()
            await projectionWriter?.invalidate()
            _ = await identityPublisher?.lock()
        }
        self.closingTask = closingTask
        await closingTask.value
    }

    private func commit(_ output: VaultSourceOutput, isSync: Bool) async throws {
        try checkOpen()
        guard output.snapshot.revision >= snapshot.revision else { return }
        var projection: VaultProjectionStatus = .unavailable
        if let projectionWriter {
            let health = await projectionWriter.project(
                revision: output.snapshot.revision,
                encryptedLoginRecords: output.encryptedLoginRecords,
                encryptedOrganizationKeys: output.encryptedOrganizationKeys
            )
            try checkOpen()
            if health == .current(revision: output.snapshot.revision), let identityPublisher {
                let identities = CredentialIdentityMapper.makeIdentities(from: output.identitySources)
                let identityHealth = await identityPublisher.publish(
                    revision: output.snapshot.revision,
                    identities: identities,
                    projectionHealth: health
                )
                projection = identityHealth == .current(revision: output.snapshot.revision)
                    ? .current(revision: output.snapshot.revision) : .stale
            } else {
                await projectionWriter.invalidate()
                _ = await identityPublisher?.clear()
                projection = .unavailable
            }
        } else {
            // A missing App Group/cache port cannot leave suggestions from an earlier session
            // advertised as though this session had a readable projection.
            _ = await identityPublisher?.clear()
        }
        try checkOpen()
        var pendingRecovery = snapshot.warnings.contains(.passkeyRegistrationRecoveryPending)
        if isSync, let registrationRecovery {
            do {
                pendingRecovery = try await registrationRecovery.reconcile(
                    identities: CredentialIdentityMapper.makeIdentities(from: output.identitySources),
                    canResolve: projection == .current(revision: output.snapshot.revision)
                )
            } catch is CancellationError { throw CancellationError() }
            catch { pendingRecovery = true }
        }
        try checkOpen()
        var warnings = output.snapshot.warnings
        if pendingRecovery, !warnings.contains(.passkeyRegistrationRecoveryPending) { warnings.append(
            .passkeyRegistrationRecoveryPending
        ) }
        snapshot = copying(
            output.snapshot,
            lastSync: isSync ? now() : snapshot.lastSuccessfulSync,
            stale: false,
            projection: projection,
            warnings: warnings
        )
        recoverySyncRevision = isSync && projection == .current(revision: snapshot.revision) ? snapshot.revision : nil
        publish()
    }

    private func copying(
        _ value: VaultSnapshot,
        lastSync: Date? = nil,
        stale: Bool,
        projection: VaultProjectionStatus? = nil,
        warnings: [VaultLoadWarning]? = nil
    ) -> VaultSnapshot {
        VaultSnapshot(
            revision: value.revision,
            items: value.items,
            lastSuccessfulSync: lastSync ?? value.lastSuccessfulSync,
            isStale: stale,
            details: value.details,
            folders: value.folders,
            collections: value.collections,
            organizationNames: value.organizationNames,
            warnings: warnings ?? value.warnings,
            projectionStatus: projection ?? value.projectionStatus
        )
    }

    private func markStale() { recoverySyncRevision = nil; snapshot = copying(snapshot, stale: true); publish() }
    private func checkOpen() throws {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
    }

    private func sessionSource() throws -> any VaultSessionSource {
        guard let source = source as? any VaultSessionSource else { throw VaultRepositoryError.unsupportedOperation }
        return source
    }

    private func acquireOperation() async {
        if operationActive { await withCheckedContinuation { operationWaiters.append($0) } }
        else { operationActive = true }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty { operationActive = false }
        else { operationWaiters.removeFirst().resume() }
    }

    private func publish() { for observer in observers.values { observer.yield(snapshot) } }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
