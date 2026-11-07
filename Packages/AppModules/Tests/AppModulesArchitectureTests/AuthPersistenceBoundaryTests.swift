import AutoFillContract
@testable import Data
import Domain
import Foundation
import SecurityStorage
import Testing

/// Pure persistence fixtures only. No SDK client, real Keychain, entitlements or network.
@Suite
struct AuthPersistenceBoundaryTests {
    private func tokens(_ label: String, generation: UInt64 = 1) -> TokenPair {
        TokenPair(
            accessToken: "test-access-\(label)",
            refreshToken: "test-refresh-\(label)",
            expiresAt: .distantFuture,
            generation: generation
        )
    }

    private func store(_ privateKeychain: AuthKeychainFixture, _ shared: AuthKeychainFixture) -> AuthCredentialStore {
        AuthCredentialStore(keychain: privateKeychain, sharedKeychain: shared, sharedLockPolicy: .processOnly)
    }

    @Test
    func freshLoginIsOneRecordAndNeverSharesTokensBeforeUnlock() throws {
        let privateKeychain = AuthKeychainFixture()
        let shared = AuthKeychainFixture()
        let auth = store(privateKeychain, shared)
        let session = try auth.saveSession(account: .fixture(), tokens: tokens("new"))
        #expect(try auth.loadSession()?.scope == session.scope)
        #expect(try auth.loadAccount() == session.account)
        #expect(try auth.loadTokens() == session.tokens)
        #expect(throws: KeychainStoreError.notFound) { try privateKeychain.read("auth.tokens") }
        #expect(throws: KeychainStoreError.notFound) { try privateKeychain.read("auth.account") }
        #expect(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
        try auth.publishForTesting()
        let proof = try #require(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()?.proof)
        let mirrored = try #require(
            try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load(requiringUnlockProof: proof)
        )
        #expect(mirrored.scope == session.scope)
        #expect(mirrored.unlockID == proof.unlockID)
    }

    @Test(arguments: ["lock", "logout", "replacement"])
    func staleFreshLoginCannotCommitOrRevokeTheNewerCapability(transition: String) throws {
        let shared = AuthKeychainFixture()
        let auth = store(AuthKeychainFixture(), shared)
        _ = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        let proof = try auth.freshLoginCommitProof()
        switch transition {
        case "lock": try auth.lockSession()
        case "logout": try auth.clearSession()
        default:
            _ = try auth.saveSession(account: .fixture(), tokens: tokens("winner"))
            try auth.publishForTesting()
        }
        let scope = try auth.loadSession()?.scope
        let savedTokens = try auth.loadTokens()
        let epoch = try auth.autofillPublicationEpoch()
        let grant = try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()?.proof

        #expect(throws: CancellationError.self) {
            try auth.saveSession(account: .fixture(), tokens: tokens("late"), requiring: proof)
        }

        #expect(try auth.loadSession()?.scope == scope)
        #expect(try auth.loadTokens() == savedTokens)
        #expect(try auth.autofillPublicationEpoch() == epoch)
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()?.proof == grant)
    }

    @Test
    func twoFreshAttemptsFromSignedOutCannotBothCommit() throws {
        let auth = store(AuthKeychainFixture(), AuthKeychainFixture())
        let first = try auth.freshLoginCommitProof()
        let second = try auth.freshLoginCommitProof()
        let winner = try auth.saveSession(account: .fixture(), tokens: tokens("first"), requiring: first).session

        #expect(throws: CancellationError.self) {
            try auth.saveSession(account: .fixture(), tokens: tokens("second"), requiring: second)
        }
        #expect(try auth.loadSession()?.scope == winner.scope)
        #expect(try auth.loadTokens() == winner.tokens)
    }

    @Test
    func sameLineageRefreshDoesNotInvalidateAFreshLoginAttempt() throws {
        let auth = store(AuthKeychainFixture(), AuthKeychainFixture())
        let previous = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        let proof = try auth.freshLoginCommitProof()
        _ = try auth.saveRefreshedTokens(
            tokens("rotated"),
            basedOnGeneration: previous.tokens.generation,
            requiringScope: previous.scope
        )

        let next = try auth.saveSession(account: .fixture(), tokens: tokens("new-login"), requiring: proof).session

        #expect(next.scope != previous.scope)
        #expect(try auth.loadTokens() == next.tokens)
    }

    @Test
    func epochReadFailureCannotOverwriteTheSavedSession() throws {
        let shared = AuthKeychainFixture()
        let auth = store(AuthKeychainFixture(), shared)
        let previous = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        let proof = try auth.freshLoginCommitProof()
        shared.accountsFailingReads.insert(AutoFillStorageKeys.sharedUnlockEpochAccount)

        #expect(throws: AuthFixtureError.self) {
            try auth.saveSession(account: .fixture(), tokens: tokens("late"), requiring: proof)
        }
        #expect(try auth.loadSession()?.scope == previous.scope)
        #expect(try auth.loadTokens() == previous.tokens)
    }

    @Test
    func invalidFreshCandidateDoesNotRevokeTheExistingGrant() throws {
        let shared = AuthKeychainFixture()
        let auth = store(AuthKeychainFixture(), shared)
        let previous = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        try auth.publishForTesting()
        let proof = try auth.freshLoginCommitProof()
        let grant = try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()?.proof
        let invalid = TokenPair(accessToken: "", refreshToken: "test-invalid", expiresAt: .distantFuture)

        #expect(throws: KeychainStoreError.decodeFailed) {
            try auth.saveSession(account: .fixture(), tokens: invalid, requiring: proof)
        }
        #expect(try auth.loadTokens() == previous.tokens)
        #expect(try auth.autofillPublicationEpoch() == proof.publicationEpoch)
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()?.proof == grant)
    }

    @Test
    func returningUnlockCapturedBeforeLockCannotAdoptTheNewEpoch() throws {
        let auth = store(AuthKeychainFixture(), AuthKeychainFixture())
        let saved = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        let captured = try auth.returningUnlockEpoch(requiringScope: saved.scope)
        try auth.lockSession()

        #expect(throws: CancellationError.self) {
            try auth.returningUnlockEpoch(requiringScope: saved.scope, expectedEpoch: captured)
        }
        #expect(try auth.loadSession()?.scope == saved.scope)
        #expect(try auth.returningUnlockEpoch(requiringScope: saved.scope) != captured)
    }

    @Test
    func biometricEnrollmentCannotWriteAfterItsUnlockWasRevoked() throws {
        let auth = store(AuthKeychainFixture(), AuthKeychainFixture())
        let saved = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        let captured = try auth.returningUnlockEpoch(requiringScope: saved.scope)
        try auth.lockSession()

        #expect(throws: CancellationError.self) {
            try auth.enableBiometricUnlock(
                key: "fake-biometric-key",
                requiringScope: saved.scope,
                publicationEpoch: captured
            )
        }
        #expect(try auth.readBiometricUserKey() == nil)
        #expect(try auth.loadAccount()?.isBiometricUnlockEnabled == false)
    }

    @Test
    func failedLoginWritePreservesThePreviousAccountTokenPair() throws {
        let privateKeychain = AuthKeychainFixture()
        let shared = AuthKeychainFixture()
        let auth = store(privateKeychain, shared)
        let old = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        try auth.publishForTesting()
        privateKeychain.accountsFailingWrites = [PrivateAuthSessionStore.key]
        #expect(throws: AuthFixtureError.self) {
            try auth.saveSession(account: .fixture(userID: "other-user"), tokens: tokens("new"))
        }
        #expect(try auth.loadSession()?.scope == old.scope)
        #expect(try auth.loadAccount() == old.account)
        #expect(try auth.loadTokens() == old.tokens)
        #expect(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
    }

    @Test
    func legacySplitTokensAreNotAnAuthenticatedSession() throws {
        let privateKeychain = AuthKeychainFixture()
        let auth = store(privateKeychain, AuthKeychainFixture())
        try privateKeychain.write(JSONEncoder().encode(StoredAuthAccount.fixture()), for: "auth.account")
        try privateKeychain.write(JSONEncoder().encode(tokens("unbound")), for: "auth.tokens")
        #expect(try auth.loadAccount() != nil)
        #expect(try auth.loadSession() == nil)
        #expect(try auth.loadTokens() == nil)
        try auth.saveSession(account: .fixture(), tokens: tokens("bound"))
        #expect(try auth.loadTokens()?.accessToken == "test-access-bound")
    }

    @Test(arguments: ["different-user", "different-server", "different-login", "legacy"])
    func higherForeignSharedGenerationsCannotReplaceThePrivateSession(kind: String) throws {
        let shared = AuthKeychainFixture()
        let auth = store(AuthKeychainFixture(), shared)
        let current = try auth.saveSession(account: .fixture(), tokens: tokens("app"))
        try auth.publishForTesting()
        let proof = try #require(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()?.proof)
        let owner: TokenAccountIdentity
        if kind == "different-user" {
            owner = TokenAccountIdentity(userID: "other-user", serverBaseURL: current.scope.account.serverBaseURL)
        } else if kind == "different-server" {
            owner = TokenAccountIdentity(
                userID: current.scope.account.userID,
                serverBaseURL: URL(string: "https://other.example.com")!
            )
        } else { owner = current.scope.account }
        let foreignScope = kind == "legacy" ? nil : TokenScope(
            account: owner,
            authenticationID: kind == "different-login" ? UUID() : current.scope.authenticationID
        )
        let foreign = SharedTokens(
            accessToken: "test-foreign-access",
            refreshToken: "test-foreign-refresh",
            expiresAt: .distantFuture,
            generation: 900,
            scope: foreignScope,
            unlockID: proof.unlockID
        )
        // Simulate a corrupt/older writer, rather than bypassing the guarded production API.
        try shared.write(JSONEncoder().encode(foreign), for: AutoFillStorageKeys.sharedTokensAccount)
        #expect(try auth.reconcileSharedTokensIfNewer() == current.tokens)
        #expect(
            try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load(requiringUnlockProof: proof) == nil
        )
    }

    @Test
    func reloginOfTheSameAccountStartsANewLineageAndRejectsAnOldAppRefresh() throws {
        let auth = store(AuthKeychainFixture(), AuthKeychainFixture())
        let old = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        let next = try auth.saveSession(account: .fixture(), tokens: tokens("new"))
        #expect(old.scope != next.scope)
        #expect(next.tokens.generation == 1)
        #expect(try auth.saveRefreshedTokens(
            tokens("late"),
            basedOnGeneration: old.tokens.generation,
            requiringScope: old.scope
        ) == nil)
        #expect(try auth.loadTokens() == next.tokens)
    }

    @Test
    func aSharedRotationSurvivesAFailedPrivateRefreshWrite() throws {
        let privateKeychain = AuthKeychainFixture()
        let shared = AuthKeychainFixture()
        let auth = store(privateKeychain, shared)
        let old = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        try auth.publishForTesting()
        privateKeychain.accountsFailingWrites = [PrivateAuthSessionStore.key]
        #expect(throws: AuthFixtureError.self) {
            try auth.saveRefreshedTokens(
                tokens("refreshed"),
                basedOnGeneration: old.tokens.generation,
                requiringScope: old.scope
            )
        }
        #expect(try auth.loadTokens() == old.tokens)
        #expect(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load()?.generation == 2)
        privateKeychain.accountsFailingWrites = []
        #expect(try auth.reconcileSharedTokensIfNewer()?.refreshToken == "test-refresh-refreshed")
    }

    @Test
    func accountSettingsUpdatePreservesTheTokenScopeAndRotation() throws {
        let auth = store(AuthKeychainFixture(), AuthKeychainFixture())
        let old = try auth.saveSession(account: .fixture(), tokens: tokens("app"))
        var account = old.account
        account.isPinUnlockEnabled = true
        try auth.save(account: account)
        #expect(try auth.loadSession()?.scope == old.scope)
        #expect(try auth.loadTokens() == old.tokens)
        #expect(try auth.loadAccount()?.isPinUnlockEnabled == true)
    }

    @Test
    func failedSharedRefreshWriteStillPersistsTheIssuedPrivatePairAndRevokesTheGrant() throws {
        let shared = AuthKeychainFixture()
        let auth = store(AuthKeychainFixture(), shared)
        let old = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        try auth.publishForTesting()
        shared.accountsFailingWrites = [AutoFillStorageKeys.sharedTokensAccount]
        #expect(throws: AuthFixtureError.self) {
            try auth.saveRefreshedTokens(
                tokens("issued"),
                basedOnGeneration: old.tokens.generation,
                requiringScope: old.scope
            )
        }
        #expect(try auth.loadTokens()?.refreshToken == "test-refresh-issued")
        #expect(try auth.loadTokens()?.generation == 2)
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
        #expect(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
    }

    @Test(arguments: [false, true])
    func dualWriteFailureReportsIndependentRevocationFailure(_ cleanupFails: Bool) throws {
        let privateKeychain = AuthKeychainFixture()
        let shared = AuthKeychainFixture()
        let auth = store(privateKeychain, shared)
        let old = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        try auth.publishForTesting()
        privateKeychain.accountsFailingWrites = [PrivateAuthSessionStore.key]
        shared.accountsFailingWrites = [AutoFillStorageKeys.sharedTokensAccount]
        if cleanupFails {
            shared.accountsFailingWrites.insert(AutoFillStorageKeys.sharedUnlockEpochAccount)
            shared.accountsFailingRemoval = [
                AutoFillStorageKeys.sharedUserKeyAccount,
                AutoFillStorageKeys.sharedTokensAccount,
            ]
        }
        #expect(throws: TokenCommitRecoveryError.rotationNotDurable(capabilityRevocationFailed: cleanupFails)) {
            try auth.saveRefreshedTokens(
                tokens("lost"),
                basedOnGeneration: old.tokens.generation,
                requiringScope: old.scope
            )
        }
        #expect(try auth.loadTokens() == old.tokens)
        let grant = try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()
        #expect((grant != nil) == cleanupFails)
    }

    @Test
    func malformedRefreshCannotBePublishedBeforePrivateValidation() throws {
        let shared = AuthKeychainFixture()
        let auth = store(AuthKeychainFixture(), shared)
        let old = try auth.saveSession(account: .fixture(), tokens: tokens("old"))
        try auth.publishForTesting()
        let invalid = TokenPair(accessToken: "", refreshToken: "test-invalid", expiresAt: .distantFuture)
        #expect(throws: KeychainStoreError.decodeFailed) {
            try auth.saveRefreshedTokens(invalid, basedOnGeneration: old.tokens.generation, requiringScope: old.scope)
        }
        #expect(try auth.loadTokens() == old.tokens)
        #expect(
            try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load()?.generation == old.tokens.generation
        )
    }

    @Test
    func invalidNewRecordDoesNotFallBackToLegacyTokensAndExplicitLogoutCanRecover() throws {
        let privateKeychain = AuthKeychainFixture()
        let auth = store(privateKeychain, AuthKeychainFixture())
        try privateKeychain.write(JSONEncoder().encode(StoredAuthAccount.fixture()), for: "auth.account")
        try privateKeychain.write(JSONEncoder().encode(tokens("legacy")), for: "auth.tokens")
        let mismatched = PersistedAuthSession(
            account: .fixture(),
            scope: TokenScope(account: StoredAuthAccount.fixture(userID: "wrong").tokenIdentity),
            tokens: tokens("wrong-owner")
        )
        try privateKeychain.write(JSONEncoder().encode(mismatched), for: PrivateAuthSessionStore.key)
        #expect(throws: KeychainStoreError.decodeFailed) { try auth.loadAccount() }
        #expect(throws: KeychainStoreError.decodeFailed) { try auth.loadTokens() }
        try auth.clearSession()
        #expect(try auth.loadAccount() == nil)
        #expect(try auth.loadTokens() == nil)
    }

    @Test
    func generationOverflowFailsClosedInsteadOfTrapping() throws {
        let privateKeychain = AuthKeychainFixture()
        let auth = store(privateKeychain, AuthKeychainFixture())
        let scope = TokenScope(account: StoredAuthAccount.fixture().tokenIdentity)
        try PrivateAuthSessionStore(keychain: privateKeychain).save(PersistedAuthSession(
            account: .fixture(),
            scope: scope,
            tokens: tokens("max", generation: .max)
        ))
        #expect(throws: KeychainStoreError.decodeFailed) {
            try auth.saveRefreshedTokens(tokens("next"), basedOnGeneration: .max, requiringScope: scope)
        }
        #expect(try auth.loadTokens()?.generation == UInt64.max)
    }

    @Test
    func legacyReadersCannotConsumeTheNewGrantAndTokens() throws {
        let shared = AuthKeychainFixture()
        let auth = store(AuthKeychainFixture(), shared)
        try shared.write(Foundation.Data("fake-legacy-key".utf8), for: AutoFillStorageKeys.legacySharedUserKeyAccount)
        try shared.write(JSONEncoder().encode(tokens("legacy")), for: AutoFillStorageKeys.legacySharedTokensAccount)
        try auth.saveSession(account: .fixture(), tokens: tokens("new"))
        try auth.publishForTesting()
        #expect(throws: KeychainStoreError.notFound) { try shared.read(AutoFillStorageKeys.legacySharedUserKeyAccount) }
        #expect(throws: KeychainStoreError.notFound) { try shared.read(AutoFillStorageKeys.legacySharedTokensAccount) }
        #expect(try shared.read(AutoFillStorageKeys.sharedUserKeyAccount).isEmpty == false)
        #expect(try shared.read(AutoFillStorageKeys.sharedTokensAccount).isEmpty == false)
    }

    @Test
    func grantPublicationRejectsMismatchedCryptoMetadataForTheSameOwner() throws {
        let auth = store(AuthKeychainFixture(), AuthKeychainFixture())
        try auth.saveSession(account: .fixture(), tokens: tokens("app"))
        let wrong = SharedAccountInfo(
            userId: "user-1",
            email: "test@example.com",
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedPrivateKey: "a-different-wrapped-key",
            serverBaseURL: URL(string: "https://vault.example.com")!
        )
        let epoch = try auth.autofillPublicationEpoch()
        #expect(throws: CancellationError.self) {
            try auth.saveSharedAutofillUserKey("fake-user-key", accountInfo: wrong, publicationEpoch: epoch)
        }
        #expect(auth.loadSharedAutofillUserKeyForTesting() == nil)
    }

    @Test
    func persistenceDescriptionsNeverPrintTokensOrWrappedKeys() throws {
        let account = StoredAuthAccount.fixture()
        let session = PersistedAuthSession(
            account: account,
            scope: TokenScope(account: account.tokenIdentity),
            tokens: tokens("secret")
        )
        for value in [String(describing: session), String(reflecting: session.tokens), String(reflecting: account)] {
            #expect(!value.contains("test-access"))
            #expect(!value.contains("fake-wrapped"))
        }
    }
}
