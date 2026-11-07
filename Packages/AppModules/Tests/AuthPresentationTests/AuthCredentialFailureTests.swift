@testable import AuthPresentation
import BitwardenSdk
@testable import Data
import Domain
import Foundation
import Networking
import Testing

@MainActor
@Suite
struct AuthCredentialFailureTests {
    @Test(arguments: [#"{"kdf":2}"#, #"{"kdf":0,"kdfIterations":-1}"#,
                      #"{"kdf":1,"kdfMemory":4294967296}"#])
    func invalidPreloginNeverRequestsTokensOrPersistsAnAccount(_ body: String) async throws {
        let http = MockHTTPClient()
        http.responses = [HTTPResponse(statusCode: 200, headers: [:], body: Foundation.Data(body.utf8))]
        let tokens = MockIdentityTokenService()
        let unlock = MockVaultUnlockService()
        let dependencies = makeDependencies(http: http, tokens: tokens, unlock: unlock)
        let environment = try ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
        let model = LoginModel(
            environment: environment,
            commands: dependencies.passwordSignInCommands(),
            onChangeServer: {},
            onTwoFactorRequired: { _ in Issue.record("Invalid prelogin must not offer 2FA") },
            onUnlocked: { _ in Issue.record("Invalid prelogin must not hand off") }
        )
        model.receive(.emailChanged("fixture@example.com"))
        model.receive(.passwordChanged("fixture-password"))
        await model.perform(.loginTapped)
        #expect(model.state.errorMessage == AuthFlowError.invalidEncryptionParameters.localizedDescription)
        #expect(!model.state.isLoading && tokens.requestCallCount == 0 && unlock.calls.isEmpty)
        #expect(try dependencies.keychainStore.loadSession() == nil)
        model.retire()
        #expect(model.state.password.isEmpty)
    }

    private func makeDependencies(
        http: MockHTTPClient,
        tokens: MockIdentityTokenService,
        unlock: MockVaultUnlockService
    ) -> AuthDependencies {
        AuthDependencies(
            httpClient: http,
            keychainStore: AuthCredentialStore(
                keychain: MockKeychainService(),
                sharedKeychain: MockKeychainService(),
                sharedLockPolicy: .processOnly
            ),
            preloginService: DefaultPreloginService(httpClient: http),
            tokenService: tokens,
            unlockService: unlock,
            biometricClient: MockBiometricClient(),
            deviceNameClient: MockDeviceNameClient()
        )
    }
}
