import AutoFillContract
@testable import Data
import Domain
import Foundation
import Testing

@Suite
struct AuthCredentialBootstrapTests {
    private let identityURL = URL(string: "https://vault.example.com/identity")!
    private func store() -> AuthCredentialStore {
        AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
    }

    @Test
    func freshBootstrapCannotBorrowTokensAndCommitsToANewLineage() async throws {
        let auth = store()
        let old = try auth.saveSession(
            account: .fixture(),
            tokens: TokenPair(
                accessToken: "fixture-old-access",
                refreshToken: "fixture-old-refresh",
                expiresAt: .distantFuture
            )
        )
        let refresh = AuthRefreshFixture()
        let provider = try auth.makeTokenProvider(identityURL: identityURL, tokenService: refresh)
        #expect(await provider.getAccessToken() == nil)
        #expect(refresh.refreshCallCount == 0)
        try await provider.storeSession(
            account: .fixture(),
            tokens: TokenPair(
                accessToken: "fixture-new-access",
                refreshToken: "fixture-new-refresh",
                expiresAt: .distantFuture
            )
        )
        #expect(await provider.getAccessToken() == "fixture-new-access")
        #expect(try await provider.validatedScope() != old.scope)
    }

    @Test(arguments: ["account", "scope", "epoch", "identity"])
    func returningBootstrapRejectsMismatchedAuthorityBeforeAccessingTokens(_ mismatch: String) throws {
        let auth = store()
        let saved = try auth.saveSession(
            account: .fixture(),
            tokens: TokenPair(
                accessToken: "fixture-access",
                refreshToken: "fixture-refresh",
                expiresAt: .distantFuture
            )
        )
        let epoch = try auth.autofillPublicationEpoch()
        let refresh = AuthRefreshFixture()
        #expect(throws: CancellationError.self) {
            try auth.makeTokenProvider(
                identityURL: mismatch == "identity" ? URL(string: "https://other.example.com/identity")! : identityURL,
                restoringAccount: mismatch == "account" ? .fixture(userID: "other-user") : saved.account,
                expectedScope: mismatch == "scope" ? TokenScope(account: saved.scope.account) : saved.scope,
                expectedPublicationEpoch: mismatch == "epoch" ? UUID() : epoch,
                tokenService: refresh
            )
        }
        try auth.expectPersistedSession(saved)
        #expect(refresh.refreshCallCount == 0)
    }

    @Test(arguments: ["http://unsafe.example.com/identity", "https://user:password@example.com/identity",
                      "https://vault.example.com/identity?secret=fixture"])
    func unsafeServerIsRejectedBeforeCapturingStorageAuthority(_ url: String) throws {
        let keychain = AuthKeychainFixture()
        let shared = AuthKeychainFixture()
        keychain.accountsFailingReads = [PrivateAuthSessionStore.key]
        shared.accountsFailingReads = [AutoFillStorageKeys.sharedUnlockEpochAccount]
        let auth = AuthCredentialStore(keychain: keychain, sharedKeychain: shared, sharedLockPolicy: .processOnly)
        #expect(throws: ServerEnvironmentError.invalidBaseURL) {
            try auth.makeTokenProvider(identityURL: URL(string: url)!, tokenService: AuthRefreshFixture())
        }
    }
}
