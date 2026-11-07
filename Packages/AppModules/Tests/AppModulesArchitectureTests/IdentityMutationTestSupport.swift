import Domain
import Foundation
import SecurityStorage

/// Explicit in-memory coordination for unit fixtures; never a production fallback.
actor IdentityMutationTestCoordinator: CredentialIdentityMutationCoordinating {
    private var active = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func withExclusiveMutation(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        if active { await withCheckedContinuation { waiters.append($0) } }
        else { active = true }
        defer {
            if waiters.isEmpty { active = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        try await operation()
    }
}

struct FileIdentityMutationTestCoordinator: CredentialIdentityMutationCoordinating {
    let lock: AsyncCrossProcessFileLock
    func withExclusiveMutation(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try await lock.withExclusiveLock(operation)
    }
}

final class IdentityMutationContentionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func record() {
        let pending = lock.withLock { seen = true; let pending = waiters; waiters = []; return pending }
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resume = lock.withLock {
                if seen { return true }
                waiters.append(continuation); return false
            }
            if resume { continuation.resume() }
        }
    }
}
