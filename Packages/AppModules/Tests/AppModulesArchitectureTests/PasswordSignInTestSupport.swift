import BitwardenSdk
import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation
import Networking

enum PasswordFlowStage: String, CaseIterable, Sendable {
    case prelogin, hash, token, unlock
}

actor PasswordFlowProbe {
    private(set) var calls: [PasswordFlowStage] = []
    func record(_ stage: PasswordFlowStage) { calls.append(stage) }
}

struct PasswordPreloginFixture: PreloginService {
    let probe: PasswordFlowProbe
    let gate: AuthOperationTestGate?
    func fetchKdf(email: String, identityURL: URL) async throws -> KeyDerivationParameters {
        await probe.record(.prelogin)
        await gate?.pause() // deliberately ignores cancellation
        return .pbkdf2(iterations: 600_000)
    }
}

@MainActor
final class PasswordDeviceNameFixture: DeviceNameClient {
    func currentDeviceName() -> String { "Fixture" }
}

actor PasswordCryptographyFixture: AuthCredentialCryptography {
    nonisolated let resource = SDKSessionClient(client: Client(noHandle: Client.NoHandle()))
    let probe: PasswordFlowProbe
    let stage: PasswordFlowStage?
    let gate: AuthOperationTestGate?
    let keyGate: AuthOperationTestGate?
    private(set) var hashEmail: String?
    private(set) var unlockPassword: String?

    init(
        probe: PasswordFlowProbe,
        stage: PasswordFlowStage? = nil,
        gate: AuthOperationTestGate? = nil,
        keyGate: AuthOperationTestGate? = nil
    ) {
        self.probe = probe; self.stage = stage; self.gate = gate; self.keyGate = keyGate
    }

    func hashPassword(email: String, password: String, kdf: KeyDerivationParameters) async throws -> String {
        hashEmail = email
        await probe.record(.hash)
        if stage == .hash { await gate?.pause() }
        return "fixture-hash"
    }

    func unlockPassword(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        password: String,
        wrappedUserKey: String,
        wrappedPrivateKey: String
    ) async throws {
        unlockPassword = password
        await probe.record(.unlock)
        if stage == .unlock { await gate?.pause() }
    }

    func decryptedUserKey() async throws -> String {
        await keyGate?.pause()
        return "fixture-decrypted-key"
    }

    func unlockBiometric(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        decryptedUserKey: String
    ) async throws { throw AuthFixtureError.operationFailed }
    func unlockPIN(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        pin: String,
        protectedUserKey: String
    ) async throws { throw AuthFixtureError.operationFailed }
}

actor PasswordTokenFixture: IdentityTokenService {
    struct Request: Sendable {
        let email: String
        let hash: String
        let twoFactor: TwoFactorSubmission?
    }

    let probe: PasswordFlowProbe
    private var outcomes: [TokenRequestOutcome]
    private var gate: AuthOperationTestGate?
    private(set) var requests: [Request] = []
    init(probe: PasswordFlowProbe, outcomes: [TokenRequestOutcome], gate: AuthOperationTestGate? = nil) {
        self.probe = probe; self.outcomes = outcomes; self.gate = gate
    }

    func pauseNextRequest(at gate: AuthOperationTestGate) { self.gate = gate }
    func requestToken(
        identityURL: URL,
        username: String,
        passwordHash: String,
        device: DeviceInfo,
        twoFactor: TwoFactorSubmission?
    ) async throws -> TokenRequestOutcome {
        requests.append(Request(email: username, hash: passwordHash, twoFactor: twoFactor))
        await probe.record(.token)
        let gate = gate
        self.gate = nil
        let outcome = outcomes.isEmpty ? .failure(message: "fixture-no-response") : outcomes.removeFirst()
        await gate?.pause()
        return outcome
    }

    func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome {
        .rejected
    }
}

func passwordTokenResponse(
    kdf: Int? = nil,
    subject: String = "fixture-user",
    refresh: String = "fixture-refresh",
    expires: Int = 3600,
    userKey: String = "wrapped-user"
) throws -> TokenSuccessResponse {
    let payload = try JSONSerialization.data(withJSONObject: ["sub": subject]).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    var body: [String: Any] = ["access_token": "header.\(payload).signature", "expires_in": expires,
                               "token_type": "Bearer", "refresh_token": refresh, "Key": userKey,
                               "PrivateKey": "wrapped-private"]
    if let kdf { body["Kdf"] = kdf }
    return try FlexibleKeyDecoding.makeDecoder().decode(
        TokenSuccessResponse.self,
        from: JSONSerialization.data(withJSONObject: body)
    )
}

@MainActor
struct PasswordFlowFixture {
    let store = AuthCredentialStore(
        keychain: AuthKeychainFixture(),
        sharedKeychain: AuthKeychainFixture(),
        sharedLockPolicy: .processOnly
    )
    let environment = try! ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
    let probe = PasswordFlowProbe()
    let crypto: PasswordCryptographyFixture
    let tokens: PasswordTokenFixture
    let commands: PasswordSignInService
    init(
        outcomes: [TokenRequestOutcome],
        pausedStage: PasswordFlowStage? = nil,
        gate: AuthOperationTestGate? = nil,
        keyGate: AuthOperationTestGate? = nil
    ) {
        crypto = PasswordCryptographyFixture(probe: probe, stage: pausedStage, gate: gate, keyGate: keyGate)
        tokens = PasswordTokenFixture(probe: probe, outcomes: outcomes, gate: pausedStage == .token ? gate : nil)
        let crypto = crypto
        commands = PasswordSignInService(
            store: store,
            prelogin: PasswordPreloginFixture(probe: probe, gate: pausedStage == .prelogin ? gate : nil),
            tokens: tokens,
            deviceName: PasswordDeviceNameFixture(),
            applicationVersion: "fixture",
            makeCryptography: { _, _, _ in crypto }
        )
    }

    func signIn() async throws -> PasswordSignInResult {
        try await commands.signIn(
            email: "  Fixture@Example.com \n",
            password: "fixture-password",
            environment: environment
        )
    }
}
