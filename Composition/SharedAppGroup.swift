import AutoFillData
import Data
import Domain
import Foundation
import SecurityStorage

/// Shared composition for all four app/extension targets. Runtime configuration and entitlements
/// are expanded from the same xcconfig values; there is no personal Team ID or default group.
enum SharedAppGroup {
    static func configuration() throws -> AppStorageConfiguration {
        try AppStorageConfiguration(
            info: (Bundle.main.infoDictionary ?? [:]).compactMapValues { $0 as? String },
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    static func validatedStorage() throws -> (configuration: AppStorageConfiguration, containerURL: URL) {
        let configuration = try configuration()
        let container = try configuration.resolveContainer {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
        return (configuration, container)
    }

    static var containerURL: URL? { try? validatedStorage().containerURL }

    static func identityMutationCoordinator(containerURL: URL?) -> any CredentialIdentityMutationCoordinating {
        SharedCredentialIdentityMutationCoordinator(lock: AsyncCrossProcessFileLock(
            containerURL: containerURL,
            filename: ".autofill-identities.lock"
        ))
    }

    static func makeTokenStore() throws -> SharedTokenStore {
        let storage = try validatedStorage()
        return SharedTokenStore(
            keychain: makeSharedKeychain(configuration: storage.configuration),
            containerURL: storage.containerURL
        )
    }

    static func makeUnlockStore() throws -> SharedAutoFillUnlockStore {
        let storage = try validatedStorage()
        return SharedAutoFillUnlockStore(
            keychain: makeSharedKeychain(configuration: storage.configuration),
            containerURL: storage.containerURL
        )
    }

    static func makePasskeyRecoveryStore() throws -> PasskeyRegistrationRecoveryStore {
        let storage = try validatedStorage()
        return PasskeyRegistrationRecoveryStore(directoryURL: storage.containerURL, authorization: try makeTokenStore())
    }

    static func makeSharedKeychain(configuration: AppStorageConfiguration) -> DefaultKeychainStore {
        DefaultKeychainStore(
            service: configuration.sharedKeychainService,
            accessGroup: configuration.sharedKeychainAccessGroup
        )
    }
}

private struct SharedCredentialIdentityMutationCoordinator: CredentialIdentityMutationCoordinating {
    let lock: AsyncCrossProcessFileLock
    func withExclusiveMutation(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try await lock.withExclusiveLock(operation)
    }
}
