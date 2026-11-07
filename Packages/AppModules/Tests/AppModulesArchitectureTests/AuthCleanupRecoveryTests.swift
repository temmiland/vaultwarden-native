import AutoFillContract
@testable import Data
import Domain
import Foundation
import SecurityStorage
import Testing

@Suite
struct AuthCleanupRecoveryTests {
    private func stores() -> (AuthKeychainFixture, AuthKeychainFixture, AuthCredentialStore) {
        let own = AuthKeychainFixture(), shared = AuthKeychainFixture()
        return (own, shared, recreate(own, shared))
    }

    private func recreate(_ own: AuthKeychainFixture, _ shared: AuthKeychainFixture) -> AuthCredentialStore {
        AuthCredentialStore(keychain: own, sharedKeychain: shared, sharedLockPolicy: .processOnly)
    }

    private func seed(_ store: AuthCredentialStore) throws -> PersistedAuthSession {
        let value = try store.saveSession(
            account: .fixture(),
            tokens: TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture)
        )
        try store.publishForTesting()
        return value
    }

    @Test
    func failedLogoutSurvivesStoreRecreationAndDeniesEveryNewAuthority() throws {
        let (own, shared, store) = stores(), saved = try seed(store)
        own.accountsFailingRemoval.insert(PrivateAuthSessionStore.key)
        #expect(throws: AuthFixtureError.self) { try store.clearSession() }
        let restored = recreate(own, shared)
        #expect(try AuthCleanupIntent.read(from: shared)?.kind == .logout)
        #expect(throws: AuthCleanupRecoveryError.pending) { try restored.loadSession() }
        #expect(throws: AuthCleanupRecoveryError.pending) { try restored.freshLoginCommitProof() }
        #expect(throws: AuthCleanupRecoveryError.pending) { try restored.returningUnlockEpoch(
            requiringScope: saved.scope
        ) }
        #expect(throws: AuthCleanupRecoveryError.pending) { try restored.tokenPersistence.commitRefresh(
            saved.tokens.versioned(generation: 2),
            basedOnGeneration: 1,
            requiringScope: saved.scope
        ) }
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
        own.accountsFailingRemoval = []
        try restored.recoverPendingCleanup()
        #expect(try restored.loadSession() == nil && AuthCleanupIntent.read(from: shared) == nil)
    }

    @Test
    func newRepositoryCannotRestoreRemainderUntilDurableLogoutReplaySucceeds() async throws {
        let (own, shared, store) = stores(); _ = try seed(store)
        own.accountsFailingRemoval.insert(PrivateAuthSessionStore.key)
        #expect(throws: AuthFixtureError.self) { try store.clearSession() }
        let repository = DefaultAuthRepository(persistence: recreate(own, shared))
        await #expect(throws: AuthFixtureError.self) { try await repository.restore() }
        #expect(await repository.currentSnapshot().state == .signedOut)
        own.accountsFailingRemoval = []
        #expect(try await repository.restore() == .signedOut)
        #expect(try AuthCleanupIntent.read(from: shared) == nil)
    }

    @Test(arguments: [AuthCleanupIntent.Kind.lock, .logout])
    func persistedPreCleanupCheckpointBlocksExtensionAndReplaysIdempotently(_ kind: AuthCleanupIntent.Kind) throws {
        let (own, shared, store) = stores(), saved = try seed(store)
        try shared.write(JSONEncoder().encode(AuthCleanupIntent(kind)), for: AuthCleanupIntent.key)
        let restored = recreate(own, shared)
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
        #expect(throws: AuthCleanupRecoveryError.pending) { try restored.loadSession() }
        try restored.recoverPendingCleanup()
        try restored.recoverPendingCleanup()
        #expect(try restored.loadSession()?.scope == (kind == .lock ? saved.scope : nil))
        #expect(try AuthCleanupIntent.read(from: shared) == nil)
    }

    @Test
    func lockCannotDowngradePendingLogoutOrClearItsDenyMarker() throws {
        let (_, shared, store) = stores(); _ = try seed(store)
        try shared.write(JSONEncoder().encode(AuthCleanupIntent(.logout)), for: AuthCleanupIntent.key)
        #expect(throws: AuthCleanupRecoveryError.pending) { try store.lockSession() }
        #expect(try AuthCleanupIntent.read(from: shared)?.kind == .logout)
    }

    @Test(arguments: ["malformed", "future", "unknown-kind"])
    func corruptIntentIsPreservedAndNeverReinterpretedAsNoCleanup(_ scenario: String) throws {
        let (_, shared, store) = stores(); _ = try seed(store)
        let data = Foundation.Data((scenario == "malformed" ? "invalid" :
                (
                    scenario == "future" ? "{\"schemaVersion\":2,\"kind\":\"logout\"}" : "{\"schemaVersion\":1,\"kind\":\"future\"}"
                )).utf8)
        try shared.write(data, for: AuthCleanupIntent.key)
        #expect(throws: KeychainStoreError.decodeFailed) { try store.recoverPendingCleanup() }
        #expect(throws: KeychainStoreError.decodeFailed) { try store.loadSession() }
        #expect(throws: KeychainStoreError.decodeFailed) { try SharedAutoFillUnlockStore(
            keychain: shared,
            lockPolicy: .processOnly
        ).load() }
        #expect(try shared.read(AuthCleanupIntent.key) == data)
    }

    @Test
    func intentReadFailureIsNotAnAbsentIntent() throws {
        let (_, shared, store) = stores(); _ = try seed(store)
        shared.accountsFailingReads.insert(AuthCleanupIntent.key)
        #expect(throws: AuthFixtureError.self) { try store.loadSession() }
        #expect(throws: AuthFixtureError.self) { try store.recoverPendingCleanup() }
        #expect(throws: AuthFixtureError.self) { try SharedAutoFillUnlockStore(
            keychain: shared,
            lockPolicy: .processOnly
        ).load() }
    }

    @Test
    func lockIntentReadFailureStillRevokesGrantAndSharedTokens() throws {
        let (_, shared, store) = stores(); _ = try seed(store)
        shared.accountsFailingReads.insert(AuthCleanupIntent.key)
        #expect(throws: AuthFixtureError.self) { try store.lockSession() }
        #expect(throws: KeychainStoreError.notFound) { try shared.read(AutoFillStorageKeys.sharedUserKeyAccount) }
        #expect(throws: KeychainStoreError.notFound) { try shared.read(AutoFillStorageKeys.sharedTokensAccount) }
    }

    @Test
    func failedFinalIntentRemovalKeepsDenyAfterAllCredentialRemoval() throws {
        let (own, shared, store) = stores(); _ = try seed(store)
        let device = try store.deviceIdentifier()
        shared.accountsFailingRemoval.insert(AuthCleanupIntent.key)
        #expect(throws: AuthFixtureError.self) { try store.clearSession() }
        #expect(throws: KeychainStoreError.notFound) { try own.read(PrivateAuthSessionStore.key) }
        #expect(throws: AuthCleanupRecoveryError.pending) { try recreate(own, shared).loadSession() }
        #expect(try store.deviceIdentifier() == device)
        shared.accountsFailingRemoval = []
        try recreate(own, shared).recoverPendingCleanup()
        #expect(try store.loadSession() == nil && AuthCleanupIntent.read(from: shared) == nil)
    }

    @Test
    func intentWriteFailureStillAttemptsIndependentCredentialAndGrantCleanup() throws {
        let (own, shared, store) = stores(); _ = try seed(store)
        shared.accountsFailingWrites.insert(AuthCleanupIntent.key)
        #expect(throws: AuthFixtureError.self) { try store.clearSession() }
        #expect(throws: KeychainStoreError.notFound) { try own.read(PrivateAuthSessionStore.key) }
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
        #expect(try AuthCleanupIntent.read(from: shared) == nil) // no false durable-journal claim
    }

    @Test
    func extensionRotationIsRetainedBeforeInstallingLockIntent() throws {
        let (own, shared, store) = stores(), saved = try seed(store)
        let sharedTokens = SharedTokenStore(keychain: shared, lockPolicy: .processOnly)
        let proof = try #require(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load()?.proof)
        try sharedTokens.withTransaction { transaction in
            try transaction.publish(saved.tokens.versioned(generation: 2), scope: saved.scope)
        }
        shared.accountsFailingRemoval.insert(AutoFillStorageKeys.sharedUserKeyAccount)
        #expect(throws: AuthFixtureError.self) { try store.lockSession() }
        #expect(try PrivateAuthSessionStore(keychain: own).load()?.tokens.generation == 2)
        #expect(try sharedTokens.load(requiringUnlockProof: proof) == nil)
        shared.accountsFailingRemoval = []
        try recreate(own, shared).recoverPendingCleanup()
        #expect(try store.loadSession()?.tokens.generation == 2)
    }

    @Test
    func repeatedRecoveryWithoutIntentNeverDeletesASuccessorSession() throws {
        let (own, shared, store) = stores(); _ = try seed(store)
        try store.clearSession()
        let successor = try seed(store)
        try recreate(own, shared).recoverPendingCleanup()
        #expect(try store.loadSession()?.scope == successor.scope)
        #expect(try SharedAutoFillUnlockStore(keychain: shared, lockPolicy: .processOnly).load() != nil)
    }
}
