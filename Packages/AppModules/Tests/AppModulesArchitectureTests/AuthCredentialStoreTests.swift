@testable import Data
import Domain
import Foundation
import Testing

@Suite
struct AuthCredentialStoreTests {
    private func makeAccount(biometricEnabled: Bool = false) -> StoredAuthAccount {
        StoredAuthAccount(
            userId: "user-1",
            email: "user@example.com",
            serverBaseURL: URL(string: "https://vault.example.com")!,
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedUserKey: "encrypted-user-key",
            encryptedPrivateKey: "encrypted-private-key",
            isBiometricUnlockEnabled: biometricEnabled
        )
    }

    @Test
    func deviceIdentifierIsGeneratedOnceAndPersisted() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )

        let first = try store.deviceIdentifier()
        let second = try store.deviceIdentifier()

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test
    func accountRoundTripsThroughKeychain() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        #expect(try store.loadAccount() == nil)

        let account = makeAccount()
        try store.save(account: account)

        #expect(try store.loadAccount() == account)
    }

    @Test
    func tokensRoundTripThroughKeychain() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let tokens = TokenPair(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )

        let persisted = try store.save(tokens: tokens)

        // `save` is allowed to assign the durable cross-process revision and its timestamp. The
        // persisted return value, rather than the pre-save request, is therefore the record that
        // must survive a Keychain round trip.
        #expect(try store.loadTokens() == persisted)
    }

    @Test
    func legacyTokenPayloadDecodesAtGenerationZero() throws {
        let legacyJSON = #"{"accessToken":"access","refreshToken":"refresh","expiresAt":1234567890}"#

        let decoded = try JSONDecoder().decode(TokenPair.self, from: Data(legacyJSON.utf8))

        #expect(decoded.generation == 0)
        #expect(decoded.updatedAt == decoded.expiresAt)
    }

    @Test
    func aStrictlyNewerSharedGenerationIsAdoptedByThePrivateStore() throws {
        let privateKeychain = AuthKeychainFixture()
        let sharedKeychain = AuthKeychainFixture()
        let store = AuthCredentialStore(
            keychain: privateKeychain,
            sharedKeychain: sharedKeychain,
            sharedLockPolicy: .processOnly
        )
        try store.save(tokens: TokenPair(
            accessToken: "app-access", refreshToken: "app-refresh", expiresAt: .distantFuture
        ))
        try store.publishForTesting()
        let mirrored = try #require(try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).load())
        let privateGeneration = try #require(try store.loadTokens()?.generation)
        try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).save(SharedTokens(
            accessToken: "extension-access",
            refreshToken: "extension-refresh",
            expiresAt: .distantFuture,
            generation: privateGeneration + 1, scope: mirrored.scope, unlockID: mirrored.unlockID
        ))

        let reconciled = try #require(try store.reconcileSharedTokensIfNewer())

        #expect(reconciled.accessToken == "extension-access")
        #expect(reconciled.refreshToken == "extension-refresh")
        #expect(try store.loadTokens() == reconciled)
    }

    @Test
    func lockPersistsANewerExtensionRefreshBeforeRevokingSharedTokens() throws {
        let sharedKeychain = AuthKeychainFixture()
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: sharedKeychain,
            sharedLockPolicy: .processOnly
        )
        try store.save(tokens: TokenPair(
            accessToken: "app-access", refreshToken: "app-refresh", expiresAt: .distantFuture
        ))
        try store.publishForTesting()
        let mirrored = try #require(try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).load())
        let privateGeneration = try #require(try store.loadTokens()?.generation)
        try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).save(SharedTokens(
            accessToken: "extension-access",
            refreshToken: "extension-refresh",
            expiresAt: .distantFuture,
            generation: privateGeneration + 1, scope: mirrored.scope, unlockID: mirrored.unlockID
        ))

        try store.lockSession()

        #expect(try store.loadTokens()?.refreshToken == "extension-refresh")
        #expect(try store.loadTokens()?.generation == privateGeneration + 1)
        #expect(try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).load() == nil)
    }

    @Test
    func failedTokenReconciliationStillAttemptsSharedCapabilityRemoval() throws {
        let privateStore = AuthKeychainFixture()
        let sharedStore = AuthKeychainFixture()
        let store = AuthCredentialStore(
            keychain: privateStore,
            sharedKeychain: sharedStore,
            sharedLockPolicy: .processOnly
        )
        try store.save(
            tokens: TokenPair(accessToken: "test-access", refreshToken: "test-refresh", expiresAt: .distantFuture)
        )
        try store.saveSharedAutofillUserKey(
            "fake-test-key",
            accountInfo: .fixture(),
            publicationEpoch: store.autofillPublicationEpoch()
        )
        privateStore.accountsFailingReads = [PrivateAuthSessionStore.key]

        #expect(throws: AuthFixtureError.self) { try store.lockSession() }

        #expect(store.loadSharedAutofillUserKeyForTesting() == nil)
        #expect(try SharedTokenStore(keychain: sharedStore, lockPolicy: .processOnly).load() == nil)
    }

    @Test
    func biometricUserKeyIsStoredAndDeletable() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        #expect(try store.readBiometricUserKey() == nil)

        try store.saveBiometricUserKey("decrypted-user-key")
        #expect(try store.readBiometricUserKey() == "decrypted-user-key")

        try store.deleteBiometricUserKey()
        #expect(try store.readBiometricUserKey() == nil)
    }

    @Test
    func biometricKeyDeletionPropagatesKeychainFailure() throws {
        let keychain = AuthKeychainFixture()
        keychain.accountsFailingRemoval = ["auth.biometricUserKey"]
        let store = AuthCredentialStore(
            keychain: keychain,
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )

        var didPropagateFailure = false
        do {
            try store.deleteBiometricUserKey()
        } catch is AuthFixtureError {
            didPropagateFailure = true
        }

        #expect(didPropagateFailure)
    }

    @Test
    func clearSessionRemovesAccountTokensAndBiometricKeyButKeepsDeviceIdentifier() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let deviceId = try store.deviceIdentifier()
        try store.save(account: makeAccount())
        try store.save(tokens: TokenPair(accessToken: "a", refreshToken: "r", expiresAt: Date()))
        try store.saveBiometricUserKey("key")
        try store.savePinProtectedUserKey("pin-key")

        try store.clearSession()

        #expect(try store.loadAccount() == nil)
        #expect(try store.loadTokens() == nil)
        #expect(try store.readBiometricUserKey() == nil)
        #expect(try store.readPinProtectedUserKey() == nil)
        #expect(try store.deviceIdentifier() == deviceId)
    }

    @Test
    func pinProtectedUserKeyIsStoredAndDeletable() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        #expect(try store.readPinProtectedUserKey() == nil)

        try store.savePinProtectedUserKey("pin-protected-user-key")
        #expect(try store.readPinProtectedUserKey() == "pin-protected-user-key")

        try store.deletePinProtectedUserKey()
        #expect(try store.readPinProtectedUserKey() == nil)
    }

    @Test
    func staleSignInScopeCannotEnrollOrClearCurrentPinSettings() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let tokens = TokenPair(accessToken: "first-access", refreshToken: "first-refresh", expiresAt: .distantFuture)
        let first = try store.saveSession(account: makeAccount(), tokens: tokens)
        try store.enrollPinProtectedUserKey(
            "first-pin-key",
            requiringScope: first.scope,
            publicationEpoch: store.autofillPublicationEpoch()
        )

        let second = try store.saveSession(account: makeAccount(), tokens: tokens)
        #expect(second.scope != first.scope)
        #expect(throws: CancellationError.self) {
            try store.enrollPinProtectedUserKey(
                "stale-pin-key",
                requiringScope: first.scope,
                publicationEpoch: store.autofillPublicationEpoch()
            )
        }
        #expect(throws: CancellationError.self) {
            try store.readPinProtectedUserKey(requiringScope: first.scope)
        }
        #expect(!store.disablePinUnlock(requiringScope: first.scope))
        #expect(try store.loadSession()?.scope == second.scope)
        #expect(try store.loadSession()?.account.isPinUnlockEnabled == false)
        #expect(try store.readPinProtectedUserKey() == nil)
    }

    @Test
    func staleSignInScopeCannotDisableCurrentBiometricSettings() throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let tokens = TokenPair(accessToken: "first-access", refreshToken: "first-refresh", expiresAt: .distantFuture)
        let first = try store.saveSession(account: makeAccount(), tokens: tokens)
        try store.enableBiometricUnlock(
            key: "first-biometric-key",
            requiringScope: first.scope,
            publicationEpoch: store.autofillPublicationEpoch()
        )

        let second = try store.saveSession(account: makeAccount(), tokens: tokens)
        #expect(second.scope != first.scope)
        #expect(throws: CancellationError.self) {
            try store.disableBiometricUnlock(requiringScope: first.scope)
        }
        #expect(try store.loadSession()?.scope == second.scope)
        #expect(try store.loadSession()?.account.isBiometricUnlockEnabled == false)
        #expect(try store.readBiometricUserKey() == nil)
    }

    @Test
    func accountDecodesWithPinFlagDefaultingToFalseWhenMissingFromLegacyPayload() throws {
        // Simulates an account persisted before PIN unlock existed - the JSON on disk has no
        // `isPinUnlockEnabled` key at all. Decoding must not fail (that would force a full
        // re-login); it should default to "not enrolled".
        let legacyJSON = """
        {
            "userId": "user-1",
            "email": "user@example.com",
            "serverBaseURL": "https://vault.example.com",
            "kdfType": 0,
            "kdfIterations": 600000,
            "encryptedUserKey": "encrypted-user-key",
            "encryptedPrivateKey": "encrypted-private-key",
            "isBiometricUnlockEnabled": true
        }
        """
        let decoded = try JSONDecoder().decode(StoredAuthAccount.self, from: Data(legacyJSON.utf8))

        #expect(decoded.isBiometricUnlockEnabled == true)
        #expect(decoded.isPinUnlockEnabled == false)
    }
}
