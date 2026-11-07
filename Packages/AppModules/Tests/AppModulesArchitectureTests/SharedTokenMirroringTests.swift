@testable import Data
import Domain
import Foundation
import Testing

/// The AutoFill extension can only *write* to the vault (i.e. save a passkey) because the app
/// mirrors its token pair into the shared Keychain group. That widens what a compromised extension
/// can do, so the lifecycle around it is a security control, not plumbing.
@Suite
struct SharedTokenMirroringTests {
    private func makeStore() -> (AuthCredentialStore, AuthKeychainFixture) {
        let shared = AuthKeychainFixture()
        return (
            AuthCredentialStore(keychain: AuthKeychainFixture(), sharedKeychain: shared, sharedLockPolicy: .processOnly),
            shared
        )
    }

    private func sharedTokens(in keychain: AuthKeychainFixture) -> SharedTokens? {
        try? SharedTokenStore(keychain: keychain, lockPolicy: .processOnly).load()
    }

    private let tokens = TokenPair(
        accessToken: "access", refreshToken: "refresh", expiresAt: Date(timeIntervalSince1970: 2_000_000)
    )

    @Test
    func savingTokensDoesNotPublishWithoutAnUnlockGrant() throws {
        let (store, shared) = makeStore()

        try store.save(tokens: tokens)

        #expect(sharedTokens(in: shared) == nil)
        try store.publishForTesting()

        #expect(sharedTokens(in: shared)?.accessToken == "access")
        #expect(sharedTokens(in: shared)?.refreshToken == "refresh")
    }

    /// A locked vault must not leave another process able to act as the user. The extension can't
    /// decrypt anything once the shared key is gone either, so the two must go together.
    @Test
    func lockingRevokesTheSharedTokensAlongsideTheVaultKey() throws {
        let (store, shared) = makeStore()
        try store.save(tokens: tokens)
        try store.saveSharedAutofillUserKey(
            "decrypted-user-key",
            accountInfo: .fixture(),
            publicationEpoch: store.autofillPublicationEpoch()
        )

        try store.lockSession()

        #expect(sharedTokens(in: shared) == nil)
        #expect(store.loadSharedAutofillUserKeyForTesting() == nil)
    }

    @Test
    func loggingOutRevokesTheSharedTokens() throws {
        let (store, shared) = makeStore()
        try store.save(tokens: tokens)

        try store.clearSession()

        #expect(sharedTokens(in: shared) == nil)
    }

    /// Locking clears the shared copy but must not disturb the app's own tokens - the account stays
    /// signed in, only the extension loses its grant.
    @Test
    func lockingLeavesTheAppsOwnTokensIntact() throws {
        let (store, _) = makeStore()
        try store.save(tokens: tokens)

        try store.lockSession()

        #expect(try store.loadTokens()?.accessToken == "access")
    }

    @Test
    func refreshingTokensUpdatesTheSharedCopyToo() throws {
        let (store, shared) = makeStore()
        try store.save(tokens: tokens)
        try store.publishForTesting()

        let refreshed = TokenPair(
            accessToken: "access-2", refreshToken: "refresh-2", expiresAt: Date(timeIntervalSince1970: 3_000_000)
        )
        try store.save(tokens: refreshed)

        #expect(sharedTokens(in: shared)?.accessToken == "access-2")
        #expect(sharedTokens(in: shared)?.refreshToken == "refresh-2")
    }
}
