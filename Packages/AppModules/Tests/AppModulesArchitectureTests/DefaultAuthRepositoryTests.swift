import Data
import Domain
import Foundation
import Testing

/// Pure state/persistence-port fixtures. No SDK, Keychain, network or sleeps.
@Suite
struct DefaultAuthRepositoryTests {
    private func account(_ id: String = "test-user") throws -> AccountSession {
        AccountSession(
            accountID: AccountID(rawValue: id),
            email: "test@example.com",
            environment: try ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
        )
    }

    @Test
    func restorePublishesLockedOnlyForAPersistedAccount() async throws {
        let empty = DefaultAuthRepository(persistence: LifecycleFixture())
        #expect(try await empty.restore() == .signedOut)

        let saved = try account()
        let repository = DefaultAuthRepository(persistence: LifecycleFixture(account: saved))
        #expect(try await repository.restore() == .locked(saved))
        #expect(try await repository.restore() == .locked(saved))
    }

    @Test
    func unlockRequiresTheCurrentAccountAndFailedUnlockReturnsToLocked() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: LifecycleFixture(account: saved))
        _ = try await repository.restore()
        await #expect(throws: AuthRepositoryError.accountChanged) {
            try await repository.beginUnlock(account: try account("other-user"))
        }
        #expect(try await repository.restore() == .locked(saved))

        try await repository.beginUnlock(account: saved)
        #expect(try await repository.restore() == .unlocking(saved))
        await repository.unlockFailed(account: saved)
        #expect(try await repository.restore() == .locked(saved))
    }

    @Test
    func completionAndExpiryAreBoundToTheAcceptedRuntimeID() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: LifecycleFixture(account: saved))
        _ = try await repository.restore()
        try await repository.beginUnlock(account: saved)
        let runtimeID = UUID()
        let completion = try await repository.completeUnlock(saved, sessionID: runtimeID)
        #expect(completion.sessionID == runtimeID)
        #expect(completion.transition == .unlockCompleted)
        #expect(try await repository.restore() == .unlocked(saved))

        await repository.markExpiring(sessionID: UUID())
        #expect(try await repository.restore() == .unlocked(saved))
        await repository.markExpiring(sessionID: runtimeID)
        #expect(try await repository.restore() == .expiring(saved))
        try await repository.lock()
        #expect(try await repository.restore() == .locked(saved))
        let locked = await repository.currentSnapshot()
        #expect(locked.sessionID == nil)
        #expect(locked.revision > completion.revision)
    }

    @Test
    func cleanupFailureLeavesRepositoryInFailClosedStateAndCanBeRetried() async throws {
        let saved = try account()
        let persistence = LifecycleFixture(account: saved)
        let repository = DefaultAuthRepository(persistence: persistence)
        _ = try await repository.restore()
        try await repository.beginUnlock(account: saved)
        try await repository.completeUnlock(saved, sessionID: UUID())

        persistence.setFailure(.lock)
        await #expect(throws: LifecycleFixtureError.lock) { try await repository.lock() }
        #expect(try await repository.restore() == .locked(saved))
        persistence.setFailure(nil)
        try await repository.lock()
        #expect(persistence.lockCount == 2)

        persistence.setFailure(.logout)
        await #expect(throws: LifecycleFixtureError.logout) { try await repository.logout() }
        #expect(try await repository.restore() == .signedOut)
        await #expect(throws: AuthRepositoryError.staleSession) {
            try await repository.completeUnlock(saved, sessionID: UUID())
        }
        await #expect(throws: AuthRepositoryError.invalidTransition) { try await repository.lock() }
        persistence.setFailure(nil)
        try await repository.logout()
        #expect(persistence.logoutCount == 2)
        await #expect(throws: AuthRepositoryError.staleSession) {
            try await repository.completeUnlock(saved, sessionID: UUID())
        }
    }

    @Test
    func sessionStreamPublishesTransitionSnapshots() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: LifecycleFixture(account: saved))
        let stream = await repository.sessionStates()
        var states = stream.makeAsyncIterator()
        #expect(await states.next()?.state == .signedOut)
        _ = try await repository.restore()
        #expect(await states.next()?.state == .locked(saved))
        try await repository.beginUnlock(account: saved)
        #expect(await states.next()?.state == .unlocking(saved))
        await repository.unlockFailed(account: saved)
        #expect(await states.next()?.state == .locked(saved))
    }
}

private enum LifecycleFixtureError: Error, Equatable { case lock, logout }

private final class LifecycleFixture: AuthSessionLifecycleStore, @unchecked Sendable {
    private let lock = NSLock()
    private var account: AccountSession?
    private var failure: LifecycleFixtureError?
    private var locks = 0
    private var logouts = 0
    init(account: AccountSession? = nil) { self.account = account }
    var lockCount: Int { lock.withLock { locks } }
    var logoutCount: Int { lock.withLock { logouts } }
    func setFailure(_ error: LifecycleFixtureError?) { lock.withLock { failure = error } }
    func restoreAccount() throws -> AccountSession? { lock.withLock { account } }
    func lockSession() throws {
        try lock.withLock {
            locks += 1
            if failure == .lock { throw LifecycleFixtureError.lock }
        }
    }

    func clearSession() throws {
        try lock.withLock {
            logouts += 1
            if failure == .logout { throw LifecycleFixtureError.logout }
            account = nil
        }
    }
}
