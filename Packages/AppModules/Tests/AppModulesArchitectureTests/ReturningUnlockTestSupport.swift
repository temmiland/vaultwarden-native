import BitwardenSdk
import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation

@MainActor
final class ReturningBiometricFixture: BiometricClient {
    var availabilityResult: BiometricAvailability = .available(.touchID)
    var evaluationResult: BiometricEvaluationResult = .succeeded
    var gate: AuthOperationTestGate?
    private(set) var evaluations = 0
    func availability() -> BiometricAvailability { availabilityResult }
    func evaluate(reason: String) async -> BiometricEvaluationResult {
        evaluations += 1
        await gate?.pause()
        return evaluationResult
    }
}

actor ReturningCryptoFixture: AuthCredentialCryptography {
    nonisolated let resource = SDKSessionClient(client: Client(noHandle: Client.NoHandle()))
    let gate: AuthOperationTestGate?
    let keyGate: AuthOperationTestGate?
    let fails: Bool
    private(set) var calls: [String] = []
    init(gate: AuthOperationTestGate? = nil, keyGate: AuthOperationTestGate? = nil, fails: Bool = false) {
        self.gate = gate; self.keyGate = keyGate; self.fails = fails
    }

    private func perform(_ method: String) async throws {
        calls.append(method)
        await gate?.pause()
        if fails { throw AuthFixtureError.operationFailed }
    }

    func hashPassword(email: String, password: String, kdf: KeyDerivationParameters) async throws -> String { "unused-hash" }
    func unlockPassword(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        password: String,
        wrappedUserKey: String,
        wrappedPrivateKey: String
    ) async throws { try await perform("password") }
    func unlockPIN(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        pin: String,
        protectedUserKey: String
    ) async throws { try await perform("pin") }
    func unlockBiometric(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        decryptedUserKey: String
    ) async throws { try await perform("biometric") }
    func decryptedUserKey() async throws -> String { await keyGate?.pause(); return "returning-decrypted-key" }
}

@MainActor
struct ReturningFlowFixture {
    let keychain = AuthKeychainFixture()
    let store: AuthCredentialStore
    let scope: TokenScope
    let stored: StoredAuthAccount
    let biometric = ReturningBiometricFixture()
    let crypto: ReturningCryptoFixture
    let begin = AuthInvocationProbe()
    let failed = AuthInvocationProbe()
    let commands: ReturningUnlockService
    init(
        method: String = "password",
        cryptoGate: AuthOperationTestGate? = nil,
        keyGate: AuthOperationTestGate? = nil,
        beginGate: AuthOperationTestGate? = nil,
        fails: Bool = false,
        beginCancelled: Bool = false
    ) throws {
        store = AuthCredentialStore(
            keychain: keychain,
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        var account = StoredAuthAccount.fixture()
        account.isPinUnlockEnabled = method == "pin"
        account.isBiometricUnlockEnabled = method == "biometric"
        stored = account
        scope = try store.saveSession(
            account: account,
            tokens: TokenPair(
                accessToken: "returning-access",
                refreshToken: "returning-refresh",
                expiresAt: .distantFuture
            )
        ).scope
        if method == "pin" { try store.savePinProtectedUserKey("returning-protected-key") }
        if method == "biometric" { try store.saveBiometricUserKey("returning-biometric-key") }
        crypto = ReturningCryptoFixture(gate: cryptoGate, keyGate: keyGate, fails: fails)
        let crypto = crypto, begin = begin, failed = failed
        commands = try ReturningUnlockService(
            account: account,
            scope: scope,
            store: store,
            tokens: AuthRefreshFixture(),
            deviceName: PasswordDeviceNameFixture(),
            biometric: biometric,
            applicationVersion: "fixture",
            beginUnlock: { _ in
                await begin.record(); await beginGate?.pause()
                if beginCancelled { throw CancellationError() }
            },
            unlockFailed: { _ in await failed.record() },
            makeCryptography: { _, _, _ in crypto }
        )
    }

    func request(_ method: String) -> ReturningUnlockMethod {
        switch method { case "pin": .pin("1234"); case "biometric": .biometric; default: .password("fixture-password") }
    }
}
