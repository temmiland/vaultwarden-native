import AppFeature
import Data
import Domain
import Foundation
import Testing

/// Deterministic security lifecycle fixtures: no SDK, real Keychain, network or sleeps.
@MainActor
@Suite
struct AppModelTests {
    private func account() throws -> AccountSession {
        AccountSession(
            accountID: AccountID(rawValue: "user"),
            email: "user@example.com",
            environment: try ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
        )
    }

    private func makeModel(
        repository: any AuthRepository,
        files: ModelTemporaryFiles = ModelTemporaryFiles(),
        timeout: ModelTimeoutDriver? = nil
    ) -> AppModel<ModelSession> {
        AppModel(
            authRepository: repository,
            timeoutDriver: timeout ?? ModelTimeoutDriver(),
            prepareAuthenticatedSession: { try await files.prepare() },
            cleanUpTemporaryFiles: { try await files.cleanUp() }
        )
    }

    @Test
    func lateRepositoryApprovalCannotReopenALockedModel() async throws {
        let saved = try account()
        let store = ModelLifecycleStore(account: saved)
        let base = DefaultAuthRepository(persistence: store)
        _ = try await base.restore()
        let gate = ModelSuspension()
        let repository = SuspendedCompletionRepository(base: base, gate: gate)
        let model = makeModel(repository: repository)
        let session = ModelSession(account: saved)

        let handoff = Task { await model.didAuthenticate(session) }
        await gate.waitUntilPaused()
        await model.lockNow()
        await gate.release()
        await handoff.value

        #expect(model.session == nil)
        #expect(!session.isActive)
        #expect(store.lockCount == 1)
        #expect(await base.currentSnapshot().state == .locked(saved))
    }

    @Test
    func noncooperativePreparationFinishesBeforeLockClosesTemporaryAccess() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: ModelLifecycleStore(account: saved))
        _ = try await repository.restore()
        let preparation = ModelSuspension()
        let files = ModelTemporaryFiles(preparationGate: preparation)
        let model = makeModel(repository: repository, files: files)
        let session = ModelSession(account: saved)

        let handoff = Task { await model.didAuthenticate(session) }
        await preparation.waitUntilPaused()
        let lock = Task { await model.lockNow() }
        await session.waitUntilRevoked()
        await preparation.release()
        await handoff.value
        await lock.value

        #expect(model.session == nil)
        #expect(await files.isAcceptingWork == false)
        #expect(await files.cleanupCount == 1)
    }

    @Test
    func cleanupFailureBlocksNewHandoffUntilRetry() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: ModelLifecycleStore(account: saved))
        _ = try await repository.restore()
        let files = ModelTemporaryFiles()
        let model = makeModel(repository: repository, files: files)
        await model.didAuthenticate(ModelSession(account: saved))
        await files.setCleanupFailure(true)

        await model.lockNow()
        let rejected = ModelSession(account: saved)
        await model.didAuthenticate(rejected)
        #expect(model.session == nil)
        #expect(model.pendingSecurityAction == .lock)
        #expect(!rejected.isActive)

        await files.setCleanupFailure(false)
        await model.retrySecurityAction()
        #expect(model.pendingSecurityAction == nil)
        if case let .locked(account) = model.state { #expect(account == saved) }
        else { Issue.record("Cleanup retry must leave the account locked") }
    }

    @Test
    func logoutDuringLockCleanupIsAppliedAfterTheInFlightLock() async throws {
        let saved = try account()
        let store = ModelLifecycleStore(account: saved)
        let repository = DefaultAuthRepository(persistence: store)
        _ = try await repository.restore()
        let cleanup = ModelSuspension()
        let files = ModelTemporaryFiles(cleanupGate: cleanup)
        let model = makeModel(repository: repository, files: files)
        let session = ModelSession(account: saved)
        await model.didAuthenticate(session)

        let lock = Task { await model.lockNow() }
        await cleanup.waitUntilPaused()
        await model.logOut()
        await cleanup.release()
        await lock.value

        #expect(model.session == nil)
        #expect(model.pendingSecurityAction == nil)
        #expect(store.logoutCount == 1)
        #expect(session.revocationReasons == [.lock, .logout])
        #expect(await repository.currentSnapshot().state == .signedOut)
    }

    @Test
    func repositoryExpiryRevokesTheModelWithoutALegacyCallback() async throws {
        let saved = try account()
        let store = ModelLifecycleStore(account: saved)
        let repository = DefaultAuthRepository(persistence: store)
        _ = try await repository.restore()
        let cleanup = ModelSuspension()
        let model = makeModel(repository: repository, files: ModelTemporaryFiles(cleanupGate: cleanup))
        await model.start()
        let session = ModelSession(account: saved)
        await model.didAuthenticate(session)

        await repository.markExpiring(sessionID: session.id)
        await cleanup.waitUntilPaused()
        #expect(model.session == nil)
        #expect(!session.isActive)
        #expect(store.logoutCount == 1)
        await cleanup.release()
    }

    @Test
    func timeoutRemainsOwnedByTheModel() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: ModelLifecycleStore(account: saved))
        _ = try await repository.restore()
        let timeout = ModelTimeoutDriver()
        let model = makeModel(repository: repository, timeout: timeout)
        await model.didAuthenticate(ModelSession(account: saved))
        timeout.action = .lock

        await model.scenePhaseChanged(to: .background)

        #expect(model.session == nil)
        #expect(timeout.inactiveCount == 1)
    }

    @Test
    func unreadableTimeoutPreferenceLocksTheVaultAndReportsWhy() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: ModelLifecycleStore(account: saved))
        _ = try await repository.restore()
        let timeout = ModelTimeoutDriver()
        timeout.error = TimeoutPreferenceReadError.read
        let model = makeModel(repository: repository, timeout: timeout)
        await model.didAuthenticate(ModelSession(account: saved))

        await model.scenePhaseChanged(to: .background)

        #expect(model.session == nil)
        #expect(model.securityErrorMessage?.contains("safety lock was requested") == true)
    }

    @Test
    func delayedExpiryCallbackCannotLogOutALaterUnlock() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: ModelLifecycleStore(account: saved))
        _ = try await repository.restore()
        let model = makeModel(repository: repository)
        let first = ModelSession(account: saved)
        await model.didAuthenticate(first)
        await model.lockNow()
        let second = ModelSession(account: saved)
        await model.didAuthenticate(second)

        await model.sessionExpired(first.id)

        #expect(model.session?.id == second.id)
        #expect(second.isActive)
    }

    @Test
    func capabilityFromBeforeLockCannotStartANewHandoff() async throws {
        let saved = try account()
        let repository = DefaultAuthRepository(persistence: ModelLifecycleStore(account: saved))
        _ = try await repository.restore()
        let model = makeModel(repository: repository)
        await model.didAuthenticate(ModelSession(account: saved))
        let late = ModelSession(account: saved)
        await model.lockNow()
        late.invalidateAuthorization()

        await model.didAuthenticate(late)

        #expect(model.session == nil)
        #expect(!late.isActive)
        #expect(await repository.currentSnapshot().state == .locked(saved))
    }

    @Test
    func authorizationFailureDuringExpiryLogsOutInsteadOfOnlyLocking() async throws {
        let saved = try account()
        let store = ModelLifecycleStore(account: saved)
        let base = DefaultAuthRepository(persistence: store)
        _ = try await base.restore()
        let gate = ModelSuspension()
        let model = makeModel(repository: SuspendedCompletionRepository(base: base, gate: gate))
        let session = ModelSession(account: saved)
        let handoff = Task { await model.didAuthenticate(session) }
        await gate.waitUntilPaused()
        await base.markExpiring(sessionID: session.id)
        session.invalidateAuthorization()
        await gate.release()
        await handoff.value

        #expect(model.session == nil)
        #expect(store.logoutCount == 1)
        #expect(store.lockCount == 0)
        #expect(await base.currentSnapshot().state == .signedOut)
    }
}

private final class ModelSession: AppSessionResource, @unchecked Sendable {
    let id = UUID()
    let account: AccountSession
    private let lock = NSLock()
    private var active = true
    private var authorizationIsActive = true
    private var reasons: [SessionRevocationReason] = []
    private var revocationWaiters: [CheckedContinuation<Void, Never>] = []
    init(account: AccountSession) { self.account = account }
    var isActive: Bool { lock.withLock { active } }
    var revocationReasons: [SessionRevocationReason] { lock.withLock { reasons } }
    func checkAccess() throws {
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
    }

    func validateAuthorization() async throws {
        try checkAccess()
        guard lock.withLock({ authorizationIsActive }) else { throw CancellationError() }
    }

    func invalidateAuthorization() { lock.withLock { authorizationIsActive = false } }
    func revoke(_ reason: SessionRevocationReason) async {
        let waiters = lock.withLock {
            active = false
            reasons.append(reason)
            let waiters = revocationWaiters
            revocationWaiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func waitUntilRevoked() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if active { revocationWaiters.append(continuation) }
                else { continuation.resume() }
            }
        }
    }
}

@MainActor
private final class ModelTimeoutDriver: AppTimeoutDriving {
    var action: AppTimeoutAction?
    var error: (any Error)?
    private(set) var inactiveCount = 0
    func noteBecameActive() {}
    func noteBecameInactive() { inactiveCount += 1 }
    func pendingAppAction() throws -> AppTimeoutAction? {
        if let error { throw error }
        return action
    }
}

private enum TimeoutPreferenceReadError: Error { case read }

private final class ModelLifecycleStore: AuthSessionLifecycleStore, @unchecked Sendable {
    private let lock = NSLock()
    private var account: AccountSession?
    private var locks = 0
    private var logouts = 0
    init(account: AccountSession) { self.account = account }
    var lockCount: Int { lock.withLock { locks } }
    var logoutCount: Int { lock.withLock { logouts } }
    func restoreAccount() throws -> AccountSession? { lock.withLock { account } }
    func lockSession() throws { lock.withLock { locks += 1 } }
    func clearSession() throws { lock.withLock { logouts += 1; account = nil } }
}

private actor ModelTemporaryFiles {
    private let preparationGate: ModelSuspension?
    private let cleanupGate: ModelSuspension?
    private var cleanupFailure = false
    private(set) var isAcceptingWork = false
    private(set) var cleanupCount = 0
    init(preparationGate: ModelSuspension? = nil, cleanupGate: ModelSuspension? = nil) {
        self.preparationGate = preparationGate
        self.cleanupGate = cleanupGate
    }

    func prepare() async throws {
        await preparationGate?.pause()
        // Intentionally noncooperative: cancellation alone cannot close this late setup result.
        isAcceptingWork = true
    }

    func cleanUp() async throws {
        await cleanupGate?.pause()
        isAcceptingWork = false
        cleanupCount += 1
        if cleanupFailure { throw CancellationError() }
    }

    func setCleanupFailure(_ value: Bool) { cleanupFailure = value }
}

private actor ModelSuspension {
    private var paused = false
    private var released = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        guard !released else { return }
        paused = true
        for waiter in pauseWaiters { waiter.resume() }
        pauseWaiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilPaused() async {
        guard !paused else { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor SuspendedCompletionRepository: AuthRepository {
    let base: DefaultAuthRepository
    let gate: ModelSuspension
    init(base: DefaultAuthRepository, gate: ModelSuspension) { self.base = base; self.gate = gate }
    func sessionStates() async -> AsyncStream<AuthSessionSnapshot> { await base.sessionStates() }
    func currentSnapshot() async -> AuthSessionSnapshot { await base.currentSnapshot() }
    func restore() async throws -> SessionState { try await base.restore() }
    func beginUnlock(account: AccountSession) async throws { try await base.beginUnlock(account: account) }
    func completeUnlock(_ account: AccountSession, sessionID: UUID) async throws -> AuthSessionSnapshot {
        let snapshot = try await base.completeUnlock(account, sessionID: sessionID)
        await gate.pause()
        return snapshot
    }

    func unlockFailed(account: AccountSession) async { await base.unlockFailed(account: account) }
    func markExpiring(sessionID: UUID) async { await base.markExpiring(sessionID: sessionID) }
    func lock() async throws { try await base.lock() }
    func logout() async throws { try await base.logout() }
}
