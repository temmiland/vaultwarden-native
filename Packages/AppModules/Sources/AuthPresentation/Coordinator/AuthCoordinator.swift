import Domain
import Foundation
import Observation

/// Typed auth flow controller. Retains one Observation model per route, injects configured
/// services and retires its screen before navigation. It never creates live dependencies.
@MainActor
@Observable
final class AuthCoordinator {
    /// Models are created when a route changes, never during body evaluation. Keeping a typed
    /// screen alive preserves edits and the submit gate through unrelated redraws.
    enum Screen {
        case serverSetup(ServerSetupModel)
        case login(LoginModel)
        case twoFactor(TwoFactorModel)
        case unlock(UnlockModel)
        case enableBiometrics(EnableBiometricsModel)
        case keychainUnavailable
    }

    @ObservationIgnored private(set) var route: AuthRoute = .serverSetup
    private(set) var keychainErrorMessage: String?
    var isConfirmingSignOut = false

    @ObservationIgnored private let commands: any AuthFlowCommands
    @ObservationIgnored private let biometricClient: any BiometricClient
    @ObservationIgnored private let onLogout: () async -> Void
    @ObservationIgnored private let onAuthenticated: (any AuthenticatedSessionCapability) -> Void
    @ObservationIgnored private let onSessionExpired: @MainActor @Sendable (UUID) -> Void
    @ObservationIgnored private var isFinishingSession = false
    @ObservationIgnored private var hasHandedOffSession = false
    private(set) var screen: Screen = .keychainUnavailable
    @ObservationIgnored private(set) var routeID = UUID()
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    init(
        commands: any AuthFlowCommands,
        biometricClient: any BiometricClient,
        onLogout: @escaping () async -> Void,
        onAuthenticated: @escaping (any AuthenticatedSessionCapability) -> Void,
        onSessionExpired: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        self.commands = commands
        self.biometricClient = biometricClient
        self.onLogout = onLogout
        self.onAuthenticated = onAuthenticated
        self.onSessionExpired = onSessionExpired
        navigate(to: .serverSetup)
    }

    deinit {
        restoreTask?.cancel()
        finishTask?.cancel()
    }

    @discardableResult
    func start() -> Task<Void, Never> {
        keychainErrorMessage = nil
        restoreTask?.cancel()
        let id = routeID
        let task = Task<Void, Never> { @MainActor [weak self] in await self?.restoreAndStart(routeID: id) }
        restoreTask = task
        return task
    }

    private func restoreAndStart(routeID id: UUID) async {
        do {
            let result = try await commands.restore()
            guard isCurrentRoute(id) else {
                if case let .returningUnlock(commands) = result { await commands.revoke() }
                return
            }
            switch result {
            case .serverSetup: navigate(to: .serverSetup)
            case let .passwordSignIn(environment, requiresStorageMigration):
                navigate(to: .login(environment: environment))
                if requiresStorageMigration {
                    keychainErrorMessage = "The saved sign-in uses an older storage format. Sign in once with your master password to securely migrate it."
                }
            case let .returningUnlock(commands):
                navigate(to: .unlock(commands: commands))
            }
        } catch {
            // Don't make a Keychain outage or malformed record look like first run. The recovery
            // route lets the user retry before intentionally continuing to a fresh sign-in.
            guard isCurrentRoute(id) else { return }
            navigate(to: .keychainUnavailable)
        }
    }

    func continueToServerSetup() {
        navigate(to: .serverSetup)
    }

    func dismissKeychainError() {
        keychainErrorMessage = nil
    }

    func requestLogout() async {
        // The app owner closes the visible auth route and performs runtime/file/persistence
        // cleanup together. A repository-only logout could skip sensitive-file recovery.
        await onLogout()
    }

    func navigate(to route: AuthRoute) {
        retireScreen()
        hasHandedOffSession = false
        isConfirmingSignOut = false
        restoreTask?.cancel()
        finishTask?.cancel()
        isFinishingSession = false
        let oldProvider = capability(in: self.route)
        let newProvider = capability(in: route)
        if let oldProvider, oldProvider.id != newProvider?.id {
            Task { await oldProvider.revoke() }
        }
        routeID = UUID()
        screen = makeScreen(for: route, routeID: routeID)
        self.route = route
    }

    /// Called when the auth UI leaves the tree (lock/logout, cancellation, or accepted handoff).
    /// A handed-off provider belongs to SessionRuntime and must not be revoked by UI teardown.
    func stop() {
        restoreTask?.cancel()
        finishTask?.cancel()
        retireScreen()
        if !hasHandedOffSession, let provider = capability(in: route) {
            Task { await provider.revoke() }
        }
        routeID = UUID()
        route = .serverSetup
        screen = .keychainUnavailable
        isFinishingSession = false
        isConfirmingSignOut = false
    }

    private func retireScreen() {
        switch screen {
        case let .serverSetup(model): model.retire()
        case let .login(model): model.retire()
        case let .twoFactor(model): model.retire()
        case let .unlock(model): model.retire()
        case let .enableBiometrics(model): model.retire()
        case .keychainUnavailable: break
        }
    }

    private func capability(in route: AuthRoute) -> (any AuthAttemptCapability)? {
        switch route {
        case let .twoFactor(context): context
        case let .enableBiometrics(context): context
        case let .unlock(commands): commands
        default: nil
        }
    }

    func isCurrentRoute(_ id: UUID) -> Bool { routeID == id && !Task.isCancelled }

    private func accept(_ context: any PendingAuthentication, routeID id: UUID, finish: Bool = false) {
        guard isCurrentRoute(id) else {
            Task { await context.revoke() }
            return
        }
        if finish { self.finish(with: context) }
        else { navigate(to: .enableBiometrics(context: context)) }
    }

    private func pendingCallback(routeID id: UUID, finish: Bool = false) -> (any PendingAuthentication) -> Void {
        { [weak self] context in
            guard let self else {
                Task { await context.revoke() }
                return
            }
            accept(context, routeID: id, finish: finish)
        }
    }

    /// Called once a session is fully ready to hand off - either the `enableBiometrics` screen
    /// finished (accepted or declined), or `UnlockModel` unlocked with Touch ID/password on an
    /// account that already had biometrics enabled, so there's nothing left to ask.
    private func finish(with context: any PendingAuthentication) {
        guard !isFinishingSession else { return }
        isFinishingSession = true
        // Registered before the session escapes this package: once the refresh token stops being
        // accepted there is no way back without re-authenticating, so the app has to be told
        // rather than left making requests that all 401.
        let onSessionExpired = onSessionExpired
        let commands = commands
        let id = routeID
        finishTask = Task { @MainActor [weak self] in
            var preparedSession: (any AuthenticatedSessionCapability)?
            do {
                guard self?.isCurrentRoute(id) == true else { throw CancellationError() }
                let session = try await commands.prepareHandoff(context, onExpired: onSessionExpired)
                preparedSession = session
                try await context.validateAuthorization()
                guard let self, isCurrentRoute(id) else { throw CancellationError() }
                try await session.validateAuthorization()
                guard isCurrentRoute(id) else { throw CancellationError() }
                try session.checkAccess()
                hasHandedOffSession = true
                onAuthenticated(session)
            } catch {
                await preparedSession?.revoke(.lock)
                await context.revoke()
                guard let self, isCurrentRoute(id) else { return }
                isFinishingSession = false
                // The enrollment screen may already have finished once and its provider is now
                // revoked. Rebuild the saved-sign-in route rather than leave a dead-end retry.
                start()
                keychainErrorMessage = "Couldn't prepare the unlocked session. Sign in again."
            }
        }
    }

    private func makeScreen(for route: AuthRoute, routeID id: UUID) -> Screen {
        switch route {
        case .serverSetup: makeServerSetupScreen(routeID: id)
        case let .login(environment): makeLoginScreen(environment: environment, routeID: id)
        case let .twoFactor(context): makeTwoFactorScreen(context: context, routeID: id)
        case let .unlock(commands): makeUnlockScreen(commands: commands, routeID: id)
        case let .enableBiometrics(context): makeEnableBiometricsScreen(context: context, routeID: id)
        case .keychainUnavailable: .keychainUnavailable
        }
    }

    private func makeServerSetupScreen(routeID id: UUID) -> Screen {
        let model = ServerSetupModel { [weak self] environment in
            guard self?.isCurrentRoute(id) == true else { return }
            self?.navigate(to: .login(environment: environment))
        }
        return .serverSetup(model)
    }

    private func makeLoginScreen(environment: ServerEnvironment, routeID id: UUID) -> Screen {
        let model = LoginModel(
            environment: environment,
            commands: commands.passwordSignIn,
            onChangeServer: { [weak self] in
                guard self?.isCurrentRoute(id) == true else { return }
                self?.navigate(to: .serverSetup)
            },
            onTwoFactorRequired: { [weak self] context in
                guard self?.isCurrentRoute(id) == true else {
                    Task { await context.revoke() }
                    return
                }
                self?.navigate(to: .twoFactor(context: context))
            },
            onUnlocked: pendingCallback(routeID: id)
        )
        return .login(model)
    }

    private func makeTwoFactorScreen(context: any AuthSecondFactorChallenge, routeID id: UUID) -> Screen {
        // Do not let a retained back-navigation callback keep password/hash/Client alive.
        let environment = context.environment
        let model = TwoFactorModel(
            context: context,
            onCancel: { [weak self] in
                guard self?.isCurrentRoute(id) == true else { return }
                self?.navigate(to: .login(environment: environment))
            },
            onUnlocked: pendingCallback(routeID: id)
        )
        return .twoFactor(model)
    }

    private func makeUnlockScreen(commands: any ReturningUnlockCommands, routeID id: UUID) -> Screen {
        let model = UnlockModel(
            commands: commands,
            onLogout: { [weak self] in
                guard self?.isCurrentRoute(id) == true else { return }
                Task {
                    guard self?.isCurrentRoute(id) == true else { return }
                    await self?.requestLogout()
                }
            },
            onUnlocked: pendingCallback(routeID: id),
            onAlreadyEnabledUnlock: pendingCallback(routeID: id, finish: true)
        )
        return .unlock(model)
    }

    private func makeEnableBiometricsScreen(context: any PendingAuthentication, routeID id: UUID) -> Screen {
        let model = EnableBiometricsModel(
            context: context,
            biometricClient: biometricClient,
            onFinished: pendingCallback(routeID: id, finish: true)
        )
        return .enableBiometrics(model)
    }
}
