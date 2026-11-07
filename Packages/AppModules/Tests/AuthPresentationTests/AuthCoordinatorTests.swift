@testable import AuthPresentation
import BitwardenSdk
@testable import Data
import Domain
import Foundation
import Testing

/// Regression fixtures without live Keychain, network, crypto or sleeps.
@MainActor
@Suite
struct AuthCoordinatorTests {
    private func makeCoordinator(
        repository: any AuthRepository,
        onLogout: @escaping () async -> Void = {},
        configuredDependencies: AuthDependencies? = nil,
        onAuthenticated: @escaping (any AuthenticatedSessionCapability) -> Void = { _ in }
    ) -> AuthCoordinator {
        let http = MockHTTPClient()
        let dependencies = AuthDependencies(
            httpClient: http,
            keychainStore: AuthCredentialStore(
                keychain: MockKeychainService(),
                sharedKeychain: MockKeychainService(),
                sharedLockPolicy: .processOnly
            ),
            preloginService: DefaultPreloginService(httpClient: http),
            tokenService: MockIdentityTokenService(),
            unlockService: MockVaultUnlockService(),
            biometricClient: MockBiometricClient(),
            deviceNameClient: MockDeviceNameClient()
        )
        let configured = configuredDependencies ?? dependencies
        return AuthCoordinator(
            commands: configured.flowCommands(repository: repository),
            biometricClient: configured.biometricClient,
            onLogout: onLogout,
            onAuthenticated: onAuthenticated,
            onSessionExpired: { _ in }
        )
    }

    @Test
    func viewConstructionKeepsTheSameLoginModelAndInput() throws {
        let coordinator = makeCoordinator(repository: DefaultAuthRepository(persistence: CoordinatorLifecycleStore()))
        coordinator.navigate(
            to: .login(environment: try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!))
        )
        guard case let .login(original) = coordinator.screen else {
            Issue.record("Expected a retained login screen"); return
        }
        original.receive(.emailChanged("edited@example.com"))

        _ = AuthFlowView(coordinator: coordinator).body
        _ = AuthFlowView(coordinator: coordinator).body

        guard case let .login(redrawn) = coordinator.screen else {
            Issue.record("A redraw must not replace the login route"); return
        }
        #expect(original === redrawn)
        #expect(redrawn.state.email == "edited@example.com")
    }

    @Test
    func callbackFromRetiredScreenCannotChangeTheCurrentRoute() async {
        let coordinator = makeCoordinator(repository: DefaultAuthRepository(persistence: CoordinatorLifecycleStore()))
        guard case let .serverSetup(retired) = coordinator.screen else {
            Issue.record("Expected server setup"); return
        }
        retired.receive(.urlTextChanged("retired.example.com"))
        let currentEnvironment = try! ServerEnvironment(baseURL: URL(string: "https://current.example.com")!)
        coordinator.navigate(to: .login(environment: currentEnvironment))

        await retired.perform(.continueTapped)

        guard case let .login(current) = coordinator.screen else {
            Issue.record("A retired callback replaced the current route"); return
        }
        #expect(current.state.environment.baseURL == currentEnvironment.baseURL)
    }

    @Test
    func routeChangeRetiresLoginAndClearsPasswordImmediately() async {
        let coordinator = makeCoordinator(repository: DefaultAuthRepository(persistence: CoordinatorLifecycleStore()))
        coordinator.navigate(
            to: .login(environment: try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!))
        )
        guard case let .login(previous) = coordinator.screen else { Issue.record("Expected login"); return }
        previous.receive(.passwordChanged("fixture-password"))

        coordinator.navigate(to: .serverSetup)
        previous.receive(.passwordChanged("must-not-be-retained"))
        await previous.perform(.loginTapped)

        #expect(previous.state.password.isEmpty)
        #expect(previous.state.errorMessage == nil)
        guard case .serverSetup = coordinator.screen else { Issue.record("Retired login replaced route"); return }
    }

    @Test
    func leavingAuthUIRetiresCurrentScreenAndAllowsCleanRestart() async {
        let coordinator = makeCoordinator(repository: DefaultAuthRepository(persistence: CoordinatorLifecycleStore()))
        coordinator.navigate(
            to: .login(environment: try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!))
        )
        guard case let .login(previous) = coordinator.screen else { Issue.record("Expected login"); return }
        previous.receive(.passwordChanged("fixture-password"))
        coordinator.stop()
        #expect(previous.state.password.isEmpty)
        guard case .keychainUnavailable = coordinator.screen else { Issue.record("Stopped route remained live"); return }

        await coordinator.start().value
        guard case .serverSetup = coordinator.screen else { Issue.record("Restart did not create a fresh route"); return }
    }

    @Test
    func UIExitAfterAcceptedHandoffDoesNotRevokeSessionOwnedProvider() async throws {
        let http = MockHTTPClient()
        let store = AuthCredentialStore(
            keychain: MockKeychainService(),
            sharedKeychain: MockKeychainService(),
            sharedLockPolicy: .processOnly
        )
        let account = StoredAuthAccount.fixture()
        let saved = try store.saveSession(account: account, tokens: TokenPair(
            accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture
        ))
        let dependencies = AuthDependencies(
            httpClient: http,
            keychainStore: store,
            preloginService: DefaultPreloginService(httpClient: http),
            tokenService: MockIdentityTokenService(),
            unlockService: MockVaultUnlockService(),
            biometricClient: MockBiometricClient(),
            deviceNameClient: MockDeviceNameClient()
        )
        let provider = AppAuthTokenProvider(
            identityURL: account.serverBaseURL.appendingPathComponent("identity"),
            keychainStore: store,
            tokenService: dependencies.tokenService,
            scope: saved.scope
        )
        let context = dependencies.pendingSession(
            client: BitwardenSdk.Client(noHandle: BitwardenSdk.Client.NoHandle()),
            provider: provider,
            account: try AccountSession(storedAccount: account)
        )
        let signal = CoordinatorLogoutSignal()
        var acceptedSession: (any AuthenticatedSessionCapability)?
        let coordinator = makeCoordinator(
            repository: DefaultAuthRepository(persistence: CoordinatorLifecycleStore()),
            configuredDependencies: dependencies,
            onAuthenticated: { session in
                acceptedSession = session
                Task { await signal.markCalled() }
            }
        )
        coordinator.navigate(to: .enableBiometrics(context: context))
        guard case let .enableBiometrics(model) = coordinator.screen else { Issue.record("Expected enrollment route"); return }
        await model.perform(.skipTapped)
        await signal.waitUntilCalled()

        coordinator.stop()
        try #require(acceptedSession).checkAccess()
        #expect(try await provider.validatedScope() == saved.scope)
        await acceptedSession?.revoke(.lock)
    }

    @Test
    func delayedRestoreCannotReplaceAnExplicitRouteChange() async {
        let gate = CoordinatorRestoreGate()
        let repository = DelayedRestoreRepository(
            base: DefaultAuthRepository(persistence: CoordinatorLifecycleStore()), gate: gate
        )
        let coordinator = makeCoordinator(repository: repository)
        let restore = coordinator.start()
        await gate.waitUntilPaused()
        let environment = try! ServerEnvironment(baseURL: URL(string: "https://current.example.com")!)
        coordinator.navigate(to: .login(environment: environment))
        await gate.release()
        await restore.value

        guard case let .login(current) = coordinator.screen else {
            Issue.record("An obsolete restore replaced the current login"); return
        }
        #expect(current.state.environment.baseURL == environment.baseURL)
    }

    @Test
    func unlockLogoutDelegatesToAppCleanupInsteadOfMutatingTheRepository() async {
        let store = CoordinatorLifecycleStore()
        let repository = DefaultAuthRepository(persistence: store)
        let signal = CoordinatorLogoutSignal()
        let coordinator = makeCoordinator(repository: repository, onLogout: { await signal.markCalled() })
        let account = StoredAuthAccount.fixture()
        let scope = TokenScope(
            account: TokenAccountIdentity(userID: account.userId, serverBaseURL: account.serverBaseURL)
        )
        let http = MockHTTPClient()
        let dependencies = AuthDependencies(
            httpClient: http,
            keychainStore: AuthCredentialStore(
                keychain: MockKeychainService(),
                sharedKeychain: MockKeychainService(),
                sharedLockPolicy: .processOnly
            ),
            preloginService: DefaultPreloginService(httpClient: http),
            tokenService: MockIdentityTokenService(),
            unlockService: MockVaultUnlockService(),
            biometricClient: MockBiometricClient(),
            deviceNameClient: MockDeviceNameClient()
        )
        let commands = try! dependencies.returningUnlockCommands(
            account: account,
            scope: scope,
            beginUnlock: { _ in },
            unlockFailed: { _ in }
        )
        coordinator.navigate(to: .unlock(commands: commands))
        guard case let .unlock(screen) = coordinator.screen else {
            Issue.record("Expected unlock"); return
        }

        await screen.perform(.logoutTapped)
        await signal.waitUntilCalled()

        #expect(store.logoutCount == 0)
    }
}

private final class CoordinatorLifecycleStore: AuthSessionLifecycleStore, @unchecked Sendable {
    private let lock = NSLock()
    private var logouts = 0
    var logoutCount: Int { lock.withLock { logouts } }
    func restoreAccount() throws -> AccountSession? { nil }
    func lockSession() throws {}
    func clearSession() throws { lock.withLock { logouts += 1 } }
}

private actor CoordinatorRestoreGate {
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

private actor CoordinatorLogoutSignal {
    private var called = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func markCalled() {
        called = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func waitUntilCalled() async {
        guard !called else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor DelayedRestoreRepository: AuthRepository {
    let base: DefaultAuthRepository
    let gate: CoordinatorRestoreGate
    init(base: DefaultAuthRepository, gate: CoordinatorRestoreGate) { self.base = base; self.gate = gate }
    func sessionStates() async -> AsyncStream<AuthSessionSnapshot> { await base.sessionStates() }
    func currentSnapshot() async -> AuthSessionSnapshot { await base.currentSnapshot() }
    func restore() async throws -> SessionState {
        let state = try await base.restore()
        await gate.pause()
        return state
    }

    func beginUnlock(account: AccountSession) async throws { try await base.beginUnlock(account: account) }
    func completeUnlock(_ account: AccountSession, sessionID: UUID) async throws -> AuthSessionSnapshot {
        try await base.completeUnlock(account, sessionID: sessionID)
    }

    func unlockFailed(account: AccountSession) async { await base.unlockFailed(account: account) }
    func markExpiring(sessionID: UUID) async { await base.markExpiring(sessionID: sessionID) }
    func lock() async throws { try await base.lock() }
    func logout() async throws { try await base.logout() }
}
