import AutoFillContract
@testable import Data
import Domain
import Foundation
import SecurityStorage
import Testing

@Suite
struct SharedKDFPublicationTests {
    private func account(
        type: Int?,
        iterations: Int? = nil,
        memory: Int? = nil,
        parallelism: Int? = nil
    ) -> StoredAuthAccount {
        StoredAuthAccount(
            userId: "user-1",
            email: "test@example.com",
            serverBaseURL: URL(string: "https://vault.example.com/")!,
            kdfType: type,
            kdfIterations: iterations,
            kdfMemory: memory,
            kdfParallelism: parallelism,
            encryptedUserKey: "fixture-wrapped-user",
            encryptedPrivateKey: "fixture-wrapped-private",
            isBiometricUnlockEnabled: false
        )
    }

    private func save(_ account: StoredAuthAccount) throws -> (AuthCredentialStore, AuthKeychainFixture) {
        let shared = AuthKeychainFixture()
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: shared,
            sharedLockPolicy: .processOnly
        )
        try store.saveSession(
            account: account,
            tokens: TokenPair(
                accessToken: "fixture-access",
                refreshToken: "fixture-refresh",
                expiresAt: .distantFuture
            )
        )
        return (store, shared)
    }

    @Test(arguments: [nil, 0, 1] as [Int?])
    func omittedLegacyParametersReachTheRealSharedWriteWithoutRewritingPrivateMetadata(_ type: Int?) throws {
        let original = account(type: type)
        let (store, shared) = try save(original)
        let expected = try original.autoFillAccountInfo()
        try store.saveSharedAutofillUserKey(
            "fixture-user-key",
            accountInfo: expected,
            publicationEpoch: store.autofillPublicationEpoch()
        )
        let grant = try #require(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load())
        #expect(grant.userKey == "fixture-user-key")
        #expect(grant.accountInfo.kdfType == (type ?? 0))
        #expect(grant.accountInfo.kdfIterations == (type == 1 ? 3 : 600_000))
        #expect(grant.accountInfo.kdfMemory == (type == 1 ? 64 : nil))
        #expect(grant.accountInfo.kdfParallelism == (type == 1 ? 4 : nil))
        #expect(grant.accountInfo.serverBaseURL == original.serverBaseURL)
        #expect(try store.loadSession()?.account == original)
        let tokens = try #require(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly)
            .load(requiringUnlockProof: grant.proof))
        #expect(try tokens.scope == store.loadSession()?.scope)
        #expect(tokens.accessToken == "fixture-access")
    }

    @Test
    func explicitArgonParametersAndOmittedMemoryUseTheSamePublicationMapping() throws {
        let original = account(type: 1, iterations: 5)
        let (store, shared) = try save(original)
        try store.saveSharedAutofillUserKey(
            "fixture-user-key",
            accountInfo: original.autoFillAccountInfo(),
            publicationEpoch: store.autofillPublicationEpoch()
        )
        let grant = try #require(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load())
        #expect(grant.accountInfo.kdfIterations == 5 && grant.accountInfo.kdfMemory == 64)
        #expect(grant.accountInfo.kdfParallelism == 4)
        #expect(try store.loadSession()?.account == original)
    }

    @Test(arguments: ["user", "email", "server", "privateKey", "type", "iterations", "memory", "parallelism"])
    func normalizationDoesNotAllowForeignOrChangedMetadataToReplaceAValidGrant(_ field: String) throws {
        let original = account(type: 1)
        let (store, shared) = try save(original)
        let expected = try original.autoFillAccountInfo()
        let epoch = try store.autofillPublicationEpoch()
        try store.saveSharedAutofillUserKey("fixture-original-key", accountInfo: expected, publicationEpoch: epoch)
        let before = try #require(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load())
        let wrong = SharedAccountInfo(
            userId: field == "user" ? "other-user" : expected.userId,
            email: field == "email" ? "other@example.com" : expected.email,
            kdfType: field == "type" ? 0 : expected.kdfType,
            kdfIterations: field == "iterations" ? 9 : expected.kdfIterations,
            kdfMemory: field == "memory" ? 128 : expected.kdfMemory,
            kdfParallelism: field == "parallelism" ? 8 : expected.kdfParallelism,
            encryptedPrivateKey: field == "privateKey" ? "other-wrapped-key" : expected.encryptedPrivateKey,
            serverBaseURL: field == "server" ? URL(string: "https://other.example.com")! : expected.serverBaseURL
        )
        #expect(throws: CancellationError.self) {
            try store.saveSharedAutofillUserKey("fixture-wrong-key", accountInfo: wrong, publicationEpoch: epoch)
        }
        let after = try #require(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load())
        #expect(after.proof == before.proof && after.userKey == before.userKey)
        #expect(try store.autofillPublicationEpoch() == epoch)
        #expect(try store.loadSession()?.account == original)
        #expect(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly)
            .load(requiringUnlockProof: after.proof)?.scope == store.loadSession()?.scope)
    }

    @Test(arguments: [-1, 2])
    func invalidStoredKDFCannotPublishAKeyOrTokens(_ type: Int) throws {
        let original = account(type: type)
        let (store, shared) = try save(original)
        #expect(throws: AuthFlowError.invalidEncryptionParameters) {
            try store.saveSharedAutofillUserKey(
                "fixture-key",
                accountInfo: .fixture(),
                publicationEpoch: store.autofillPublicationEpoch()
            )
        }
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
        #expect(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
        #expect(try store.loadSession()?.account == original)
    }

    @Test
    func canonicalLegacyMetadataCannotReuseAPreLockPublicationEpoch() throws {
        let original = account(type: 1)
        let (store, shared) = try save(original)
        let epoch = try store.autofillPublicationEpoch()
        try store.lockSession()
        #expect(throws: CancellationError.self) {
            try store.saveSharedAutofillUserKey(
                "fixture-late-key",
                accountInfo: original.autoFillAccountInfo(),
                publicationEpoch: epoch
            )
        }
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
    }
}
