@testable import Data
import Domain
import Foundation
import Testing

@Suite
struct DefaultVaultRepositoryTests {
    @Test
    func observerGetsInitialThenSuccessfulSnapshot() async throws {
        let expected = snapshot(revision: 4, itemName: "Primary login")
        let source = ScriptedVaultSnapshotSource(results: [.success(expected)])
        let repository = DefaultVaultRepository(source: source, now: { .distantFuture })
        let stream = await repository.observeVault()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        #expect(initial?.revision == 0)
        #expect(initial?.items.isEmpty == true)

        try await repository.sync()

        let refreshed = await iterator.next()
        #expect(refreshed?.revision == 4)
        #expect(refreshed?.items == expected.items)
        #expect(refreshed?.lastSuccessfulSync == .distantFuture)
        #expect(refreshed?.isStale == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentSyncsShareOneTransportOperation() async throws {
        let source = GatedVaultSnapshotSource()
        let repository = DefaultVaultRepository(source: source)
        let first = Task { try await repository.sync() }
        await source.waitUntilRequested()
        let second = Task { try await repository.sync() }
        while await repository.activeSyncConsumerCount < 2 {
            try Task.checkCancellation()
            await Task.yield()
        }

        #expect(await source.requestCount() == 1)
        await source.succeed(with: snapshot(revision: 1, itemName: "Shared result"))
        try await first.value
        try await second.value

        #expect((await repository.currentSnapshot()).revision == 1)
        #expect(await source.requestCount() == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingOneConsumerDoesNotCancelTheSharedSync() async throws {
        let source = GatedVaultSnapshotSource()
        let repository = DefaultVaultRepository(source: source)
        let cancelledConsumer = Task { try await repository.sync() }
        await source.waitUntilRequested()
        let remainingConsumer = Task { try await repository.sync() }
        while await repository.activeSyncConsumerCount < 2 {
            try Task.checkCancellation()
            await Task.yield()
        }

        cancelledConsumer.cancel()
        await source.succeed(with: snapshot(revision: 3, itemName: "Still completes"))

        await #expect(throws: CancellationError.self) {
            try await cancelledConsumer.value
        }
        try await remainingConsumer.value
        #expect((await repository.currentSnapshot()).revision == 3)
        #expect(await source.requestCount() == 1)
    }

    @Test
    func failedRefreshKeepsExistingItemsAndMarksThemStale() async throws {
        let initial = snapshot(revision: 2, itemName: "Still available")
        let source = ScriptedVaultSnapshotSource(results: [.failure(TestRemoteError.offline)])
        let repository = DefaultVaultRepository(source: source, initialSnapshot: initial)

        await #expect(throws: TestRemoteError.offline) {
            try await repository.sync()
        }

        let current = await repository.currentSnapshot()
        #expect(current.revision == initial.revision)
        #expect(current.items == initial.items)
        #expect(current.isStale)
    }

    @Test
    func olderServerRevisionCannotReplaceCurrentSnapshot() async throws {
        let current = snapshot(revision: 8, itemName: "Current")
        let older = snapshot(revision: 7, itemName: "Old")
        let source = ScriptedVaultSnapshotSource(results: [.success(older)])
        let repository = DefaultVaultRepository(source: source, initialSnapshot: current)

        try await repository.sync()

        #expect(await repository.currentSnapshot() == current)
    }

    @Test
    func lockClearsSnapshotAndRejectsAnInFlightResponse() async throws {
        let source = GatedVaultSnapshotSource()
        let repository = DefaultVaultRepository(
            source: source,
            initialSnapshot: snapshot(revision: 5, itemName: "Secret")
        )
        let request = Task { try await repository.sync() }
        await source.waitUntilRequested()

        await repository.lock()
        let locked = await repository.currentSnapshot()
        #expect(locked.revision == 6)
        #expect(locked.items.isEmpty)
        #expect(locked.lastSuccessfulSync == nil)

        await source.succeed(with: snapshot(revision: 99, itemName: "Must not reappear"))
        await #expect(throws: CancellationError.self) {
            try await request.value
        }
        #expect((await repository.currentSnapshot()).items.isEmpty)
    }

    private func snapshot(revision: UInt64, itemName: String) -> VaultSnapshot {
        VaultSnapshot(
            revision: revision,
            items: [VaultItemSummary(
                id: CipherID(rawValue: "cipher-\(revision)"),
                kind: .login,
                name: itemName,
                subtitle: nil,
                isFavorite: false,
                isEditable: true
            )],
            lastSuccessfulSync: .distantPast,
            isStale: false
        )
    }
}

private enum TestRemoteError: Error, Equatable {
    case offline
}

private actor ScriptedVaultSnapshotSource: VaultSnapshotSource {
    private var results: [Result<VaultSnapshot, TestRemoteError>]

    init(results: [Result<VaultSnapshot, TestRemoteError>]) {
        self.results = results
    }

    func fetchVaultSnapshot() async throws -> VaultSnapshot {
        try results.removeFirst().get()
    }
}

private actor GatedVaultSnapshotSource: VaultSnapshotSource {
    private var calls = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var responses: [CheckedContinuation<VaultSnapshot, Error>] = []
    private var completedSnapshot: VaultSnapshot?

    func fetchVaultSnapshot() async throws -> VaultSnapshot {
        calls += 1
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        // Unexpected extra requests still finish so requestCount assertions report a failure,
        // rather than one continuation being overwritten or a late request hanging forever.
        if let completedSnapshot { return completedSnapshot }
        return try await withCheckedThrowingContinuation { responses.append($0) }
    }

    func waitUntilRequested() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func requestCount() -> Int { calls }

    func succeed(with snapshot: VaultSnapshot) {
        completedSnapshot = snapshot
        let waiting = responses
        responses.removeAll()
        for response in waiting { response.resume(returning: snapshot) }
    }
}
