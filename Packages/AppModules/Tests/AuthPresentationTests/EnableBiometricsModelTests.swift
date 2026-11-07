@testable import AuthPresentation
import BitwardenSdk
import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation
import Testing

@MainActor
@Suite
struct EnableBiometricsModelTests {
    private func makeContext(unlockService: MockVaultUnlockService) throws -> (
        any PendingAuthentication,
        AuthCredentialStore
    ) {
        let keychainStore = AuthCredentialStore(
            keychain: MockKeychainService(),
            sharedKeychain: MockKeychainService(),
            sharedLockPolicy: .processOnly
        )
        try keychainStore.save(account: StoredAuthAccount(
            userId: "user-1",
            email: "user@example.com",
            serverBaseURL: URL(string: "https://vault.example.com")!,
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedUserKey: "encrypted-user-key",
            encryptedPrivateKey: "encrypted-private-key",
            isBiometricUnlockEnabled: false,
            isPinUnlockEnabled: false
        ))
        _ = try keychainStore.save(
            tokens: TokenPair(accessToken: "test-access", refreshToken: "test-refresh", expiresAt: .distantFuture)
        )
        let session = try #require(try keychainStore.loadSession())
        let tokenProvider = AppAuthTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            keychainStore: keychainStore,
            tokenService: MockIdentityTokenService(), scope: session.scope
        )
        let context = PendingAuthSession(
            account: try AccountSession(storedAccount: session.account),
            cryptography: SDKAuthCredentialCryptography(
                resource: SDKSessionClient(client: Client(noHandle: Client.NoHandle())),
                unlockService: unlockService
            ),
            provider: tokenProvider, store: keychainStore
        )
        return (context, keychainStore)
    }

    private func makeDependencies(
        unlockService: MockVaultUnlockService,
        keychainStore: AuthCredentialStore
    ) -> AuthDependencies {
        let httpClient = MockHTTPClient()
        return AuthDependencies(
            httpClient: httpClient,
            keychainStore: keychainStore,
            preloginService: DefaultPreloginService(httpClient: httpClient),
            tokenService: MockIdentityTokenService(),
            unlockService: unlockService,
            biometricClient: MockBiometricClient(),
            deviceNameClient: MockDeviceNameClient()
        )
    }

    /// Regression test: the AutoFill extension can only function if the main app shares a current
    /// decrypted user key after every unlock - not just when the user opts into Touch ID.
    @Test
    func appearedSharesTheDecryptedKeyWithTheAutofillExtensionRegardlessOfBiometricChoice() async throws {
        let unlockService = MockVaultUnlockService()
        unlockService.decryptedUserKeyToReturn = "the-decrypted-key"
        let (context, keychainStore) = try makeContext(unlockService: unlockService)
        let dependencies = makeDependencies(unlockService: unlockService, keychainStore: keychainStore)
        let model = EnableBiometricsModel(
            context: context,
            biometricClient: dependencies.biometricClient,
            onFinished: { _ in }
        )

        await model.perform(.appeared)

        #expect(keychainStore.loadSharedAutofillUserKeyForTesting() == "the-decrypted-key")
        #expect(keychainStore.loadSharedAccountInfoForTesting()?.userId == "user-1")
        #expect(keychainStore.loadSharedAccountInfoForTesting()?.encryptedPrivateKey == "encrypted-private-key")
    }

    @Test
    func appearedDoesNotSurfaceAnErrorWhenSharingTheKeyFails() async throws {
        let unlockService = MockVaultUnlockService()
        unlockService.errorToThrow = MockUnlockServiceError()
        let (context, keychainStore) = try makeContext(unlockService: unlockService)
        let dependencies = makeDependencies(unlockService: unlockService, keychainStore: keychainStore)
        let model = EnableBiometricsModel(
            context: context,
            biometricClient: dependencies.biometricClient,
            onFinished: { _ in }
        )

        await model.perform(.appeared)

        #expect(model.state.errorMessage == nil)
    }
}
