import AutoFillContract
import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation
import Testing

@Suite
struct AuthKeyDerivationMappingTests {
    @Test(arguments: [KeyDerivationParameters.pbkdf2(iterations: 123_456),
                      .argon2id(iterations: 5, memory: 32, parallelism: 2)])
    func omittedTokenMetadataPersistsTheActualPreloginParameters(_ parameters: KeyDerivationParameters) throws {
        let account = try response().makeStoredAccount(
            userID: "fixture-user",
            email: "fixture@example.com",
            serverBaseURL: URL(string: "https://vault.example.com/base/")!,
            parameters: parameters
        )
        #expect(try account.keyDerivationParameters == parameters)
        #expect(account.serverBaseURL.absoluteString == "https://vault.example.com/base/")
        #expect(
            try JSONDecoder().decode(StoredAuthAccount.self, from: JSONEncoder().encode(account)).keyDerivationParameters == parameters
        )
        let shared = try account.autoFillAccountInfo()
        #expect(try SDKAutoFillAccountMapper.kdf(for: shared) == SDKKeyDerivationMapper.kdf(for: parameters))
        #expect(account.kdfType != nil && account.kdfIterations != nil)
    }

    @Test
    func partialArgonMetadataUsesTheSamePreloginValues() throws {
        let token = response(type: 1, iterations: 5)
        let account = try token.makeStoredAccount(
            userID: "fixture-user",
            email: "fixture@example.com",
            serverBaseURL: URL(string: "https://vault.example.com")!,
            parameters: .argon2id(iterations: 5, memory: 32, parallelism: 2)
        )
        #expect(account.kdfMemory == 32 && account.kdfParallelism == 2)
    }

    @Test(arguments: [-1, 2, Int.max])
    func invalidOrDifferentTokenMetadataCannotCreateAnUnlockableRecord(_ type: Int) {
        #expect(throws: AuthFlowError.invalidEncryptionParameters) {
            _ = try response(type: type).makeStoredAccount(
                userID: "fixture-user",
                email: "fixture@example.com",
                serverBaseURL: URL(string: "https://vault.example.com")!,
                parameters: .pbkdf2(iterations: 600_000)
            )
        }
    }

    @Test
    func tokenMetadataMustAgreeWithTheKeysActuallyDerived() {
        for token in [response(type: 1, iterations: 3), response(type: 0, iterations: 10)] {
            #expect(throws: AuthFlowError.invalidEncryptionParameters) {
                _ = try token.makeStoredAccount(
                    userID: "fixture-user",
                    email: "fixture@example.com",
                    serverBaseURL: URL(string: "https://vault.example.com")!,
                    parameters: .pbkdf2(iterations: 600_000)
                )
            }
        }
    }

    @Test
    func legacyArgonRecordsUseArgonDefaultsInTheAppAndExtension() throws {
        let account = StoredAuthAccount(
            userId: "fixture-user",
            email: "fixture@example.com",
            serverBaseURL: URL(string: "https://vault.example.com")!,
            kdfType: 1,
            kdfIterations: nil,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedUserKey: "wrapped-user",
            encryptedPrivateKey: "wrapped-private",
            isBiometricUnlockEnabled: false
        )
        #expect(try account.keyDerivationParameters == .argon2id(iterations: 3, memory: 64, parallelism: 4))
        let shared = try account.autoFillAccountInfo()
        #expect(shared.kdfIterations == 3 && shared.kdfMemory == 64 && shared.kdfParallelism == 4)
        #expect(try SDKAutoFillAccountMapper.kdf(for: shared) == .argon2id(iterations: 3, memory: 64, parallelism: 4))
    }

    @Test(arguments: [-1, 0, Int(UInt32.max) + 1])
    func badStoredAccountDoesNotPublishGuessedSharedParameters(_ count: Int) {
        let account = StoredAuthAccount(
            userId: "fixture-user",
            email: "fixture@example.com",
            serverBaseURL: URL(string: "https://vault.example.com")!,
            kdfType: 0,
            kdfIterations: count,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedUserKey: "wrapped-user",
            encryptedPrivateKey: "wrapped-private",
            isBiometricUnlockEnabled: false
        )
        #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try account.keyDerivationParameters }
        #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try account.autoFillAccountInfo() }
    }

    @Test
    func credentialWireDescriptionsAreRedacted() {
        let token = response()
        let submission = TwoFactorSubmission(code: "fixture-totp", provider: 0, remember: true)
        let device = DeviceInfo(identifier: "fixture-device-id", name: "fixture-personal-name")
        for value in [String(describing: token), String(reflecting: token),
                      String(describing: TokenRequestOutcome.success(token)), String(reflecting: submission),
                      String(reflecting: device)] {
            for secret in ["fixture-access", "fixture-refresh", "wrapped-user", "wrapped-private",
                           "fixture-totp", "fixture-device-id", "fixture-personal-name"] {
                #expect(!value.contains(secret))
            }
        }
    }

    private func response(type: Int? = nil, iterations: Int? = nil) -> TokenSuccessResponse {
        TokenSuccessResponse(
            accessToken: "fixture-access",
            expiresIn: 3600,
            tokenType: "Bearer",
            refreshToken: "fixture-refresh",
            key: "wrapped-user",
            privateKey: "wrapped-private",
            kdf: type,
            kdfIterations: iterations,
            kdfMemory: nil,
            kdfParallelism: nil
        )
    }
}
