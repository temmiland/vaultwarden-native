@testable import AuthPresentation
import Domain
import Foundation
import Testing

/// The whole controller (including restore/handoff) can now run without importing Data or SDK.
@MainActor
@Suite
struct AuthControllerPortTests {
    private let environment = try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
    private func coordinator(
        _ commands: ControllerFlowFixture,
        onAuthenticated: @escaping (any AuthenticatedSessionCapability) -> Void = { _ in }
    ) -> AuthCoordinator {
        AuthCoordinator(
            commands: commands,
            biometricClient: MockBiometricClient(),
            onLogout: {},
            onAuthenticated: onAuthenticated,
            onSessionExpired: { _ in }
        )
    }

    @Test
    func obsoleteRestoreRevokesItsLateReturningCapabilityWithoutReplacingTheRoute() async {
        let gate = ControllerPortGate()
        let returning = ControllerReturningFixture(environment: environment)
        let flow = ControllerFlowFixture(restore: .returningUnlock(returning), restoreGate: gate)
        let controller = coordinator(flow)
        let restore = controller.start()
        await gate.waitUntilPaused()
        controller.navigate(to: .login(environment: environment))
        await gate.release()
        await restore.value
        #expect(await returning.revoked.wasCalled)
        guard case .login = controller.screen else { Issue.record("Stale restore replaced the route"); return }
    }

    @Test
    func restoreFailureShowsRecoveryInsteadOfPretendingThisIsFirstRun() async {
        let flow = ControllerFlowFixture(restore: .serverSetup)
        flow.failRestore = true
        let controller = coordinator(flow)
        await controller.start().value
        guard case .keychainUnavailable = controller.screen else { Issue.record("Restore failure bypassed recovery"); return }
    }

    @Test
    func routeChangeRevokesNoncooperativeLatePreparedRuntimeInsteadOfAcceptingIt() async {
        let gate = ControllerPortGate()
        let pending = ControllerPendingFixture(environment: environment)
        let session = ControllerSessionFixture(account: pending.account)
        let flow = ControllerFlowFixture(restore: .serverSetup, handoff: session, handoffGate: gate)
        var accepted = 0
        let controller = coordinator(flow, onAuthenticated: { _ in accepted += 1 })
        controller.navigate(to: .enableBiometrics(context: pending))
        guard case let .enableBiometrics(model) = controller.screen else { Issue.record("Expected enrollment"); return }
        await model.perform(.skipTapped)
        await gate.waitUntilPaused()
        controller.navigate(to: .login(environment: environment))
        await gate.release()
        await session.revoked.wait()
        #expect(accepted == 0)
        guard case .login = controller.screen else { Issue.record("Late handoff replaced the route"); return }
    }

    @Test
    func acceptedDomainRuntimeSurvivesControllerTeardown() async throws {
        let pending = ControllerPendingFixture(environment: environment)
        let session = ControllerSessionFixture(account: pending.account)
        let flow = ControllerFlowFixture(restore: .serverSetup, handoff: session)
        let accepted = ControllerPortSignal()
        let controller = coordinator(flow, onAuthenticated: { capability in
            #expect(capability.id == session.id)
            Task { await accepted.mark() }
        })
        controller.navigate(to: .enableBiometrics(context: pending))
        guard case let .enableBiometrics(model) = controller.screen else { Issue.record("Expected enrollment"); return }
        await model.perform(.skipTapped)
        await accepted.wait()
        controller.stop()
        #expect(await session.revoked.wasCalled == false)
        try await session.validateAuthorization()
        try session.checkAccess()
        await session.revoke(.lock)
    }
}

@MainActor
private final class ControllerFlowFixture: AuthFlowCommands {
    let passwordSignIn: any PasswordSignInCommands = ControllerPasswordFixture()
    let restored: AuthRestoreResult
    let restoreGate: ControllerPortGate?
    let handoff: ControllerSessionFixture?
    let handoffGate: ControllerPortGate?
    var failRestore = false
    init(
        restore: AuthRestoreResult,
        restoreGate: ControllerPortGate? = nil,
        handoff: ControllerSessionFixture? = nil,
        handoffGate: ControllerPortGate? = nil
    ) {
        restored = restore; self.restoreGate = restoreGate; self.handoff = handoff; self.handoffGate = handoffGate
    }

    func restore() async throws -> AuthRestoreResult {
        await restoreGate?.pause()
        if failRestore { throw AuthRepositoryError.accountChanged }
        return restored // deliberately ignores cancellation
    }

    func prepareHandoff(
        _ pending: any PendingAuthentication,
        onExpired: @escaping @MainActor @Sendable (UUID) -> Void
    ) async throws -> any AuthenticatedSessionCapability {
        await handoffGate?.pause()
        return try #require(handoff) // deliberately ignores cancellation
    }
}

private struct ControllerPasswordFixture: PasswordSignInCommands {
    func signIn(email: String, password: String, environment: ServerEnvironment) async throws -> PasswordSignInResult {
        .rejected(.invalidCredentials)
    }
}

@MainActor
private final class ControllerReturningFixture: ReturningUnlockCommands {
    nonisolated let id = UUID()
    let account: ReturningUnlockAccount
    let revoked = ControllerPortSignal()
    init(environment: ServerEnvironment) {
        account = ReturningUnlockAccount(
            session: AccountSession(
                accountID: AccountID(rawValue: "fixture-user"),
                email: "fixture@example.com",
                environment: environment
            ),
            isBiometricUnlockEnabled: false,
            isPinUnlockEnabled: false
        )
    }

    func availability() -> ReturningUnlockAvailability {
        ReturningUnlockAvailability(isPinAvailable: false, isBiometricAvailable: false, biometryKind: .unknown)
    }

    func unlock(using method: ReturningUnlockMethod) async -> ReturningUnlockResult { .cancelled }
    func revoke() async { await revoked.mark() }
}

private actor ControllerPendingFixture: PendingAuthentication {
    nonisolated let id = UUID()
    nonisolated let account: AccountSession
    init(environment: ServerEnvironment) {
        account = AccountSession(
            accountID: AccountID(rawValue: "fixture-user"),
            email: "fixture@example.com",
            environment: environment
        )
    }

    func validateAuthorization() async throws { try Task.checkCancellation() }
    func publishAutoFillUnlock() async {}
    func enableBiometricUnlock() async throws {}
    func revoke() async {}
}

private struct ControllerSessionFixture: AuthenticatedSessionCapability {
    let id = UUID()
    let account: AccountSession
    let revoked = ControllerPortSignal()
    func checkAccess() throws { try Task.checkCancellation() }
    func validateAuthorization() async throws {
        if await revoked.wasCalled { throw CancellationError() }
    }

    func revoke(_ reason: SessionRevocationReason) async { await revoked.mark() }
}

private actor ControllerPortSignal {
    private(set) var wasCalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func mark() { wasCalled = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
    func wait() async {
        if wasCalled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor ControllerPortGate {
    private let paused = ControllerPortSignal()
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        // Registration must precede waking the test driver.
        await withCheckedContinuation { continuation = $0; Task { await paused.mark() } }
    }

    func waitUntilPaused() async { await paused.wait() }
    func release() { continuation?.resume(); continuation = nil }
}
