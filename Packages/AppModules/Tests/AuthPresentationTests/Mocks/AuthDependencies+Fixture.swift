import BitwardenSDKAdapter
import Data
import Domain
import Foundation
import Networking

/// Test-only assembly for existing integration fixtures. Production presentation accepts only
/// Domain commands; live assembly is Data.DefaultAuthFlowService.
struct AuthDependencies: Sendable {
    let httpClient: HTTPClient
    let keychainStore: AuthCredentialStore
    let preloginService: PreloginService
    let tokenService: IdentityTokenService
    let unlockService: VaultUnlockService
    let biometricClient: any BiometricClient
    let deviceNameClient: any DeviceNameClient

    @MainActor
    func flowCommands(repository: any AuthRepository) -> any AuthFlowCommands {
        DefaultAuthFlowService(
            store: keychainStore,
            repository: repository,
            prelogin: preloginService,
            tokens: tokenService,
            biometric: biometricClient,
            deviceName: deviceNameClient,
            applicationVersion: "0.0.0",
            unlockService: unlockService
        )
    }

    func passwordSignInCommands() -> any PasswordSignInCommands {
        PasswordSignInService(
            store: keychainStore,
            prelogin: preloginService,
            tokens: tokenService,
            deviceName: deviceNameClient,
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            unlockService: unlockService
        )
    }

    @MainActor
    func returningUnlockCommands(
        account: StoredAuthAccount,
        scope: TokenScope,
        beginUnlock: @escaping @Sendable (AccountSession) async throws -> Void,
        unlockFailed: @escaping @Sendable (AccountSession) async -> Void
    ) throws -> any ReturningUnlockCommands {
        try ReturningUnlockService(
            account: account,
            scope: scope,
            store: keychainStore,
            tokens: tokenService,
            deviceName: deviceNameClient,
            biometric: biometricClient,
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            beginUnlock: beginUnlock,
            unlockFailed: unlockFailed,
            unlockService: unlockService
        )
    }
}
