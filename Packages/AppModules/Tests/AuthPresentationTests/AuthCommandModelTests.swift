@testable import AuthPresentation
import Domain
import Foundation
import Testing

/// Domain-only fakes demonstrate that login/TOTP models no longer need wire/store/SDK fixtures.
@MainActor
@Suite
struct AuthCommandModelTests {
    private let environment = try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)

    @Test(arguments: [false, true])
    func retiredLoginRevokesLateDomainCapabilityWithoutHandoff(_ twoFactor: Bool) async throws {
        let gate = AuthCommandGate()
        let pending = try AuthPendingFixture(environment: environment)
        let challenge = AuthChallengeFixture(environment: environment, pending: pending)
        let result: PasswordSignInResult = twoFactor ? .twoFactorRequired(challenge) : .unlocked(pending)
        let model = LoginModel(
            environment: environment,
            commands: AuthCommandFixture(result: result, gate: gate),
            onChangeServer: {},
            onTwoFactorRequired: { _ in Issue.record("Retired challenge callback") },
            onUnlocked: { _ in Issue.record("Retired pending callback") }
        )
        model.receive(.emailChanged("fixture@example.com"))
        model.receive(.passwordChanged("fixture-password"))
        let submission = Task { await model.perform(.loginTapped) }
        await gate.waitUntilPaused()
        model.retire()
        await gate.release()
        await submission.value
        #expect(model.state.password.isEmpty && model.state.errorMessage == nil && !model.state.isLoading)
        if twoFactor { #expect(await challenge.revocationCount == 1) }
        else { #expect(await pending.revocationCount == 1) }
    }

    @Test(arguments: [false, true])
    func successfulLoginClearsPasswordBeforeItsDomainCallback(_ twoFactor: Bool) async throws {
        let pending = try AuthPendingFixture(environment: environment)
        let challenge = AuthChallengeFixture(environment: environment, pending: pending)
        let result: PasswordSignInResult = twoFactor ? .twoFactorRequired(challenge) : .unlocked(pending)
        weak var current: LoginModel?
        var callbackCount = 0
        let checkCallback = {
            #expect(current?.state.password.isEmpty == true && current?.state.isLoading == false)
            callbackCount += 1
        }
        let model = LoginModel(
            environment: environment,
            commands: AuthCommandFixture(result: result),
            onChangeServer: {},
            onTwoFactorRequired: { _ in checkCallback() },
            onUnlocked: { _ in checkCallback() }
        )
        current = model
        model.receive(.emailChanged("fixture@example.com"))
        model.receive(.passwordChanged("fixture-password"))
        await model.perform(.loginTapped)
        #expect(callbackCount == 1)
        #expect(await pending.revocationCount == 0)
        #expect(await challenge.revocationCount == 0)
    }

    @Test
    func TOTPModelClearsCodeBeforeCallbackAndRetirementDoesNotRevokeTransferredPending() async throws {
        let pending = try AuthPendingFixture(environment: environment)
        let challenge = AuthChallengeFixture(environment: environment, pending: pending)
        weak var current: TwoFactorModel?
        var callbackCount = 0
        let model = TwoFactorModel(context: challenge, onCancel: {}, onUnlocked: { _ in
            #expect(current?.state.code.isEmpty == true && current?.state.isLoading == false)
            callbackCount += 1
            current?.retire()
        })
        current = model
        model.receive(.codeChanged("123456"))
        await model.perform(.submitTapped)
        #expect(callbackCount == 1)
        #expect(await pending.revocationCount == 0)
        #expect(model.state.code.isEmpty && !model.state.isLoading && model.state.errorMessage == nil)
    }

    @Test(arguments: [false, true])
    func returningModelClearsBothSecretsBeforeEitherDomainHandoff(_ offer: Bool) async throws {
        let pending = try AuthPendingFixture(environment: environment)
        let commands = AuthReturningFixture(
            account: ReturningUnlockAccount(
                session: pending.account,
                isBiometricUnlockEnabled: !offer,
                isPinUnlockEnabled: true
            ),
            result: .unlocked(pending, offerBiometricEnrollment: offer)
        )
        weak var current: UnlockModel?
        var callbackCount = 0
        let check = {
            #expect(current?.state.password.isEmpty == true && current?.state.pin.isEmpty == true)
            #expect(current?.state.isLoading == false)
            callbackCount += 1
            current?.retire()
        }
        let model = UnlockModel(
            commands: commands,
            onLogout: {},
            onUnlocked: { _ in check() },
            onAlreadyEnabledUnlock: { _ in check() }
        )
        current = model
        model.receive(.passwordChanged("fixture-password"))
        model.receive(.pinChanged("1234"))
        await model.perform(.unlockWithPasswordTapped)
        #expect(callbackCount == 1)
        #expect(await pending.revocationCount == 0)
    }

    @Test
    func retiredReturningModelRevokesANoncooperativeLatePendingResult() async throws {
        let pending = try AuthPendingFixture(environment: environment)
        let gate = AuthCommandGate()
        let commands = AuthReturningFixture(
            account: ReturningUnlockAccount(
                session: pending.account,
                isBiometricUnlockEnabled: false,
                isPinUnlockEnabled: false
            ),
            result: .unlocked(pending, offerBiometricEnrollment: true),
            gate: gate
        )
        let model = UnlockModel(
            commands: commands,
            onLogout: {},
            onUnlocked: { _ in Issue.record("Retired callback") },
            onAlreadyEnabledUnlock: { _ in Issue.record("Retired callback") }
        )
        model.receive(.passwordChanged("fixture-password"))
        let operation = Task { await model.perform(.unlockWithPasswordTapped) }
        await gate.waitUntilPaused()
        model.retire()
        await gate.release()
        await operation.value
        #expect(await pending.revocationCount == 1)
        #expect(model.state.password.isEmpty && model.state.pin.isEmpty && model.state.errorMessage == nil)
    }

    @Test
    func typedPINRecoveryUpdatesPresentationWithoutStorageOrSDKDependencies() async throws {
        let pending = try AuthPendingFixture(environment: environment)
        let commands = AuthReturningFixture(
            account: ReturningUnlockAccount(
                session: pending.account,
                isBiometricUnlockEnabled: false,
                isPinUnlockEnabled: true
            ),
            result: .rejected(.pinCounterFailed(cleanupConfirmed: false))
        )
        commands.disablePINOnCompletion = true
        let model = UnlockModel(commands: commands, onLogout: {}, onUnlocked: { _ in }, onAlreadyEnabledUnlock: { _ in })
        await model.perform(.appeared)
        #expect(model.state.isPinAvailable)
        model.receive(.pinChanged("1234"))
        await model.perform(.unlockWithPinTapped)
        #expect(!model.state.account.isPinUnlockEnabled && !model.state.isPinAvailable)
        #expect(model.state.pin.isEmpty && !model.state.isLoading)
        #expect(
            model.state.errorMessage == ReturningUnlockFailure.pinCounterFailed(cleanupConfirmed: false).localizedDescription
        )
    }
}

@MainActor
private final class AuthReturningFixture: ReturningUnlockCommands {
    nonisolated let id = UUID()
    var account: ReturningUnlockAccount
    let result: ReturningUnlockResult
    let gate: AuthCommandGate?
    var disablePINOnCompletion = false
    init(account: ReturningUnlockAccount, result: ReturningUnlockResult, gate: AuthCommandGate? = nil) {
        self.account = account; self.result = result; self.gate = gate
    }

    func availability() -> ReturningUnlockAvailability {
        ReturningUnlockAvailability(
            isPinAvailable: account.isPinUnlockEnabled,
            isBiometricAvailable: account.isBiometricUnlockEnabled,
            biometryKind: .touchID
        )
    }

    func unlock(using method: ReturningUnlockMethod) async -> ReturningUnlockResult {
        await gate?.pause()
        if disablePINOnCompletion { account.isPinUnlockEnabled = false }
        return result
    }

    func revoke() async {} // deliberately noncooperative; model must reject a late result itself
}

private struct AuthCommandFixture: PasswordSignInCommands {
    let result: PasswordSignInResult
    var gate: AuthCommandGate? = nil
    func signIn(email: String, password: String, environment: ServerEnvironment) async throws -> PasswordSignInResult {
        await gate?.pause()
        return result // deliberately noncooperative
    }
}

private actor AuthPendingFixture: PendingAuthentication {
    nonisolated let id = UUID()
    nonisolated let account: AccountSession
    private(set) var revocationCount = 0
    init(environment: ServerEnvironment) throws {
        account = AccountSession(
            accountID: AccountID(rawValue: "fixture-user"),
            email: "fixture@example.com",
            environment: environment
        )
    }

    func revoke() { revocationCount += 1 }
    func validateAuthorization() async throws { if revocationCount > 0 { throw CancellationError() } }
    func publishAutoFillUnlock() async {}
    func enableBiometricUnlock() async throws {}
}

private actor AuthChallengeFixture: AuthSecondFactorChallenge {
    nonisolated let id: UUID
    nonisolated let environment: ServerEnvironment
    nonisolated let availableProviders = [0]
    let pending: AuthPendingFixture
    private var transferred = false
    private(set) var revocationCount = 0
    init(environment: ServerEnvironment, pending: AuthPendingFixture) {
        id = pending.id; self.environment = environment; self.pending = pending
    }

    func submitTOTP(code: String, remember: Bool) async throws -> PasswordSignInResult {
        transferred = true
        return .unlocked(pending)
    }

    func revoke() { if !transferred { revocationCount += 1 } }
}

private actor AuthCommandGate {
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { pending in
            paused = true; continuation = pending
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilPaused() async { if !paused { await withCheckedContinuation { waiters.append($0) } } }
    func release() { continuation?.resume(); continuation = nil }
}
