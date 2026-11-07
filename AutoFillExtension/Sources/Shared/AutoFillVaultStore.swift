import AutoFillContract
import AutoFillData
import Data
import Foundation
import SecurityStorage

/// Extension composition only. Runtime, credential queries and passkey assertions belong to
/// AppModules.AutoFillData; platform completion and SDK user verification stay in OS adapters.
enum AutoFillVaultStore {
    static var cacheStore: LegacyAutoFillCacheStore {
        get throws {
            let storage = try SharedAppGroup.validatedStorage()
            let tokens = SharedTokenStore(
                keychain: SharedAppGroup.makeSharedKeychain(configuration: storage.configuration),
                containerURL: storage.containerURL
            )
            return LegacyAutoFillCacheStore(directoryURL: storage.containerURL, authorization: tokens)
        }
    }

    static func makeUnlockedSession() async throws -> ExtensionVaultSession {
        let unlockStore: SharedAutoFillUnlockStore
        let unlock: SharedAutoFillUnlock
        do {
            unlockStore = try SharedAppGroup.makeUnlockStore()
            guard let current = try unlockStore.load() else { throw AutoFillOperationError.noSharedKey }
            unlock = current
        } catch let error as AutoFillOperationError { throw error }
        catch { throw AutoFillOperationError.keychainUnavailable }
        let cacheStore = try cacheStore
        guard let cache = try cacheStore.read() else { throw AutoFillOperationError.noCache }
        try cache.validate(for: unlock.proof.account)
        guard let revision = cache.revision else { throw AutoFillOperationError.noCache }
        let session = try ExtensionVaultSession(
            accountInfo: unlock.accountInfo,
            proof: unlock.proof,
            cacheRevision: revision,
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            currentProof: { try unlockStore.load()?.proof },
            readCache: { try cacheStore.read() }
        )
        try await session.initialize(userKey: unlock.userKey, organizationKeys: cache.organizationKeys)
        return session
    }
}
