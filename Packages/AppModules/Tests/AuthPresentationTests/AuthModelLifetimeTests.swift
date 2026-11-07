@testable import AuthPresentation
import BitwardenSdk
import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation
import Observation
import Testing

/// Controlled suspension points; no sleeps, real server, biometric prompts or SDK crypto.
@MainActor
@Suite
struct AuthModelLifetimeTests {
    private func dependencies(
        prelogin: (any PreloginService)? = nil,
        token: (any IdentityTokenService)? = nil,
        biometric: (any BiometricClient)? = nil
    ) -> AuthDependencies {
        let http = MockHTTPClient()
        return AuthDependencies(
            httpClient: http,
            keychainStore: AuthCredentialStore(
                keychain: MockKeychainService(),
                sharedKeychain: MockKeychainService(),
                sharedLockPolicy: .processOnly
            ),
            preloginService: prelogin ?? DefaultPreloginService(httpClient: http),
            tokenService: token ?? MockIdentityTokenService(),
            unlockService: MockVaultUnlockService(),
            biometricClient: biometric ?? MockBiometricClient(),
            deviceNameClient: MockDeviceNameClient()
        )
    }

    private func login(dependencies: AuthDependencies, onChangeServer: @escaping () -> Void = {}) -> LoginModel {
        LoginModel(
            environment: try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!),
            commands: dependencies.passwordSignInCommands(),
            onChangeServer: onChangeServer,
            onTwoFactorRequired: { _ in Issue.record("Retired login must not hand off 2FA") },
            onUnlocked: { _ in Issue.record("Retired login must not hand off a session") }
        )
    }

    private func twoFactorContext(dependencies: AuthDependencies) -> any AuthSecondFactorChallenge {
        let environment = try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
        let provider = try! dependencies.keychainStore.makeTokenProvider(
            identityURL: environment.identityURL,
            tokenService: dependencies.tokenService
        )
        return PasswordSecondFactorChallenge(
            email: "fixture@example.com", password: "fixture-password", hash: "fixture-hash",
            kdf: .pbkdf2(iterations: 600_000),
            environment: environment,
            device: DeviceInfo(identifier: "fixture-device", name: "Fixture"), availableProviders: [0, 1],
            crypto: SDKAuthCredentialCryptography(
                resource: SDKSessionClient(client: Client(noHandle: Client.NoHandle())),
                unlockService: dependencies.unlockService
            ),
            provider: provider, store: dependencies.keychainStore, tokens: dependencies.tokenService
        )
    }

    @Test
    func retirementCancelsOwnedTaskAndRejectsDuplicateOrLaterOperations() async {
        let lifetime = AuthOperationLifetime()
        let gate = AuthModelGate()
        var sawCancellation = false
        var unexpectedCalls = 0
        let first = Task {
            await lifetime.run {
                await gate.pause()
                sawCancellation = Task.isCancelled
            }
        }
        await gate.waitUntilPaused()
        await lifetime.run { unexpectedCalls += 1 }
        lifetime.retire()
        await gate.release()
        await first.value
        await lifetime.run { unexpectedCalls += 1 }
        #expect(sawCancellation)
        #expect(unexpectedCalls == 0)
        #expect(!lifetime.isRunning)
    }

    @Test
    func callerCancellationReachesScreenOwnedTask() async {
        let lifetime = AuthOperationLifetime()
        let gate = AuthModelGate()
        var sawCancellation = false
        let caller = Task {
            await lifetime.run {
                await gate.pause()
                sawCancellation = Task.isCancelled
            }
        }
        await gate.waitUntilPaused()
        caller.cancel()
        await gate.release()
        await caller.value
        #expect(sawCancellation)
        #expect(!lifetime.isRetired)
        #expect(!lifetime.isRunning)
    }

    @Test
    func completedOperationsAllowRetryAndExposeTheirResultSynchronously() async {
        let lifetime = AuthOperationLifetime()
        var count = 0
        await lifetime.run { count += 1 }
        #expect(count == 1)
        await lifetime.run { count += 1 }
        #expect(count == 2)
    }

    @Test
    func alreadyCancelledCallerCannotStartAnOperation() async {
        let lifetime = AuthOperationLifetime()
        var count = 0
        let caller = Task { await lifetime.run { count += 1 } }
        caller.cancel()
        await caller.value
        #expect(count == 0)
    }

    @Test
    func observationTracksDirectModelStateWithoutAnotherPublishedCopy() {
        let model = login(dependencies: dependencies())
        let signal = ObservationSignal()
        withObservationTracking {
            _ = model.state.email
        } onChange: {
            signal.markChanged()
        }
        model.receive(.emailChanged("edited@example.com"))
        #expect(model.state.email == "edited@example.com")
        #expect(signal.hasChanged)
    }

    @Test
    func serverSwitchClearsPasswordBeforeNavigationCallback() async {
        var callbackSawEmptyPassword = false
        weak var current: LoginModel?
        let model = login(dependencies: dependencies(), onChangeServer: {
            callbackSawEmptyPassword = current?.state.password.isEmpty == true
        })
        current = model
        model.receive(.passwordChanged("fixture-password"))
        await model.perform(.useDifferentServerTapped)
        #expect(callbackSawEmptyPassword)
    }

    @Test
    func retiringLoginDuringPreloginClearsSecretsAndSuppressesLateFailure() async {
        let gate = AuthModelGate()
        let model = login(dependencies: dependencies(prelogin: PausedPrelogin(gate: gate)))
        model.receive(.emailChanged("fixture@example.com"))
        model.receive(.passwordChanged("fixture-password"))
        let submission = Task { await model.perform(.loginTapped) }
        await gate.waitUntilPaused()
        await model.perform(.loginTapped)
        model.retire()
        #expect(model.state.password.isEmpty)
        model.receive(.passwordChanged("must-not-be-retained"))
        await gate.release()
        await submission.value
        await model.perform(.loginTapped)
        #expect(await gate.pauseCount == 1)
        #expect(model.state.password.isEmpty)
        #expect(model.state.errorMessage == nil)
        #expect(!model.state.isLoading)
    }

    @Test
    func cancelledLoginClearsPasswordEvenIfPreloginIgnoresCancellationAndThrowsOtherError() async {
        let gate = AuthModelGate()
        let model = login(dependencies: dependencies(prelogin: PausedPrelogin(gate: gate)))
        model.receive(.emailChanged("fixture@example.com"))
        model.receive(.passwordChanged("fixture-password"))
        let submission = Task { await model.perform(.loginTapped) }
        await gate.waitUntilPaused()
        submission.cancel()
        await gate.release()
        await submission.value
        #expect(model.state.password.isEmpty)
        #expect(model.state.errorMessage == nil)
    }

    @Test
    func twoFactorCancelClearsCodeBeforeCallbackAndDropsRetryContext() async {
        let dependencies = dependencies()
        weak var current: TwoFactorModel?
        var callbackSawEmptyCode = false
        let model = TwoFactorModel(
            context: twoFactorContext(dependencies: dependencies),
            onCancel: { callbackSawEmptyCode = current?.state.code.isEmpty == true },
            onUnlocked: { _ in }
        )
        current = model
        model.receive(.codeChanged("123456"))
        await model.perform(.cancelTapped)
        model.receive(.codeChanged("654321"))
        await model.perform(.submitTapped)
        #expect(callbackSawEmptyCode)
        #expect(model.state.providers == [.authenticator, .email])
        #expect(!model.state.isLoading)
        #expect(model.state.errorMessage == nil)
    }

    @Test
    func retiringTwoFactorDuringRequestDropsCodeAndSuppressesLateError() async {
        let gate = AuthModelGate()
        let dependencies = dependencies(token: PausedTokenService(gate: gate))
        let model = TwoFactorModel(
            context: twoFactorContext(dependencies: dependencies),
            onCancel: {},
            onUnlocked: { _ in Issue.record("Retired 2FA handed off") }
        )
        model.receive(.codeChanged("123456"))
        let submission = Task { await model.perform(.submitTapped) }
        await gate.waitUntilPaused()
        await model.perform(.submitTapped)
        model.retire()
        #expect(model.state.code.isEmpty)
        model.receive(.codeChanged("must-not-be-retained"))
        await gate.release()
        await submission.value
        await model.perform(.submitTapped)
        #expect(await gate.pauseCount == 1)
        #expect(model.state.code.isEmpty)
        #expect(model.state.errorMessage == nil)
        #expect(!model.state.isLoading)
    }

    @Test
    func retiredBiometricEvaluationCannotEnrollOrFinish() async throws {
        let gate = AuthModelGate()
        let dependencies = dependencies(biometric: PausedBiometricClient(gate: gate))
        let account = StoredAuthAccount.fixture()
        let saved = try dependencies.keychainStore.saveSession(account: account, tokens: TokenPair(
            accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture
        ))
        let provider = AppAuthTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            keychainStore: dependencies.keychainStore,
            tokenService: dependencies.tokenService,
            scope: saved.scope
        )
        let context = dependencies.pendingSession(
            client: Client(noHandle: Client.NoHandle()),
            provider: provider,
            account: try AccountSession(storedAccount: account)
        )
        var didFinish = false
        let model = EnableBiometricsModel(
            context: context,
            biometricClient: dependencies.biometricClient,
            onFinished: { _ in didFinish = true }
        )
        let submission = Task { await model.perform(.enableTapped) }
        await gate.waitUntilPaused()
        model.retire()
        await gate.release()
        await submission.value
        await model.perform(.skipTapped)
        #expect(!didFinish)
        #expect(!model.state.isProcessing)
        #expect(model.state.errorMessage == nil)
        #expect(try dependencies.keychainStore.loadAccount()?.isBiometricUnlockEnabled == false)
    }

    @Test
    func retiringUnlockBeforeAuthorizationReturnsClearsBothSecretsWithoutCrypto() async throws {
        let gate = AuthModelGate()
        let dependencies = dependencies()
        let account = StoredAuthAccount.fixture()
        let saved = try dependencies.keychainStore.saveSession(account: account, tokens: TokenPair(
            accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture
        ))
        let commands = try dependencies.returningUnlockCommands(
            account: account,
            scope: saved.scope,
            beginUnlock: { _ in await gate.pause() },
            unlockFailed: { _ in }
        )
        let model = UnlockModel(
            commands: commands,
            onLogout: {},
            onUnlocked: { _ in Issue.record("Retired unlock handed off") },
            onAlreadyEnabledUnlock: { _ in Issue.record("Retired unlock handed off") }
        )
        model.receive(.passwordChanged("fixture-password"))
        model.receive(.pinChanged("1234"))
        let submission = Task { await model.perform(.unlockWithPasswordTapped) }
        await gate.waitUntilPaused()
        model.retire()
        #expect(model.state.password.isEmpty)
        #expect(model.state.pin.isEmpty)
        model.receive(.passwordChanged("must-not-be-retained"))
        await gate.release()
        await submission.value
        #expect(model.state.password.isEmpty)
        #expect(model.state.pin.isEmpty)
        #expect(model.state.errorMessage == nil)
        #expect(!model.state.isLoading)
    }
}

private actor AuthModelGate {
    private(set) var pauseCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        pauseCount += 1
        await withCheckedContinuation { pending in
            continuation = pending
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilPaused() async {
        guard pauseCount == 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() { continuation?.resume(); continuation = nil }
}

private struct PausedPrelogin: PreloginService {
    let gate: AuthModelGate
    func fetchKdf(email: String, identityURL: URL) async throws -> KeyDerivationParameters {
        await gate.pause()
        throw PreloginError.server(statusCode: 503)
    }
}

private struct PausedTokenService: IdentityTokenService {
    let gate: AuthModelGate
    func requestToken(
        identityURL: URL,
        username: String,
        passwordHash: String,
        device: DeviceInfo,
        twoFactor: TwoFactorSubmission?
    ) async throws -> TokenRequestOutcome {
        await gate.pause()
        throw PreloginError.server(statusCode: 503)
    }

    func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome { .retryable(
        .transport
    ) }
}

@MainActor
private final class PausedBiometricClient: BiometricClient {
    let gate: AuthModelGate
    init(gate: AuthModelGate) { self.gate = gate }
    func availability() -> BiometricAvailability { .available(.touchID) }
    func evaluate(reason: String) async -> BiometricEvaluationResult {
        await gate.pause()
        return .succeeded
    }
}

private final class ObservationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var hasChanged: Bool { lock.withLock { changed } }
    func markChanged() { lock.withLock { changed = true } }
}
