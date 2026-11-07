@testable import Data
import Domain
import Foundation
import Testing

@Suite
struct AppAuthTokenProviderTests {
    private let identityURL = URL(string: "https://vault.example.com/identity")!

    @Test
    func returnsCachedTokenWhenNotExpired() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        try keychain.save(tokens: TokenPair(
            accessToken: "still-valid",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600)
        ))
        let tokenService = AuthRefreshFixture()
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: tokenService,
            scope: try? keychain.loadSession()?.scope
        )

        let token = await provider.getAccessToken()

        #expect(token == "still-valid")
        #expect(tokenService.refreshCallCount == 0)
    }

    @Test
    func adoptsANewerExtensionRefreshBeforeStartingAnotherRefresh() async throws {
        let sharedKeychain = AuthKeychainFixture()
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: sharedKeychain,
            sharedLockPolicy: .processOnly
        )
        try keychain.save(tokens: TokenPair(
            accessToken: "app-access", refreshToken: "app-refresh", expiresAt: .distantPast
        ))
        try keychain.publishForTesting()
        let mirrored = try #require(try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).load())
        let generation = try #require(try keychain.loadTokens()?.generation)
        try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).save(SharedTokens(
            accessToken: "extension-access",
            refreshToken: "extension-refresh",
            expiresAt: .distantFuture,
            generation: generation + 1, scope: mirrored.scope, unlockID: mirrored.unlockID
        ))
        let tokenService = AuthRefreshFixture()
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: tokenService, scope: try? keychain.loadSession()?.scope
        )

        let token = await provider.getAccessToken()

        #expect(token == "extension-access")
        #expect(tokenService.refreshCallCount == 0)
        #expect(try keychain.loadTokens()?.refreshToken == "extension-refresh")
    }

    @Test
    func refreshesWhenExpiredAndPersistsNewTokens() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        try keychain.save(tokens: TokenPair(
            accessToken: "expired",
            refreshToken: "refresh-me",
            expiresAt: Date().addingTimeInterval(-3600)
        ))
        let tokenService = AuthRefreshFixture()
        tokenService.refreshOutcome = .success(RefreshedTokenPayload(
            accessToken: "brand-new-token",
            refreshToken: "brand-new-refresh",
            expiresIn: 3600,
            tokenType: "Bearer"
        ))
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: tokenService,
            scope: try? keychain.loadSession()?.scope
        )

        let token = await provider.getAccessToken()

        #expect(token == "brand-new-token")
        #expect(tokenService.refreshCallCount == 1)
        #expect(try keychain.loadTokens()?.accessToken == "brand-new-token")
        #expect(try keychain.loadTokens()?.refreshToken == "brand-new-refresh")
    }

    @Test
    func returnsNilWhenNoTokensStored() async {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: AuthRefreshFixture(), scope: try? keychain.loadSession()?.scope
        )

        let token = await provider.getAccessToken()

        #expect(token == nil)
    }

    @Test
    func returnsNilWhenRefreshFails() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        try keychain.save(tokens: TokenPair(
            accessToken: "expired",
            refreshToken: "refresh-me",
            expiresAt: Date().addingTimeInterval(-3600)
        ))
        let tokenService = AuthRefreshFixture()
        tokenService.refreshOutcome = .retryable(.transport)
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: tokenService,
            scope: try? keychain.loadSession()?.scope
        )

        let expiry = ExpiryProbe()
        await provider.setSessionExpiredHandler { Task { await expiry.record() } }

        let token = await provider.getAccessToken()

        #expect(token == nil)
        #expect(!(await expiry.wasReported()))
        #expect(try keychain.loadTokens()?.refreshToken == "refresh-me")
    }

    @Test
    func onlyAnExplicitRefreshRejectionExpiresTheSession() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        try keychain.save(tokens: TokenPair(
            accessToken: "expired",
            refreshToken: "revoked",
            expiresAt: Date().addingTimeInterval(-3600)
        ))
        let tokenService = AuthRefreshFixture()
        tokenService.refreshOutcome = .rejected
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: tokenService,
            scope: try? keychain.loadSession()?.scope
        )
        let expiry = ExpiryProbe()
        await provider.setSessionExpiredHandler { Task { await expiry.record() } }

        #expect(await provider.getAccessToken() == nil)
        await Task.yield()

        #expect(await expiry.wasReported())
    }

    @Test
    func aLateRefreshCannotRestoreTokensAfterRevocationAndLogout() async throws {
        let privateStore = AuthKeychainFixture()
        let sharedStore = AuthKeychainFixture()
        let keychain = AuthCredentialStore(
            keychain: privateStore,
            sharedKeychain: sharedStore,
            sharedLockPolicy: .processOnly
        )
        try keychain.save(
            tokens: TokenPair(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantPast)
        )
        let barrier = RefreshBarrier()
        let service = AuthRefreshFixture()
        service.refreshOutcome = .success(RefreshedTokenPayload(
            accessToken: "late-access",
            refreshToken: "late-refresh",
            expiresIn: 3600,
            tokenType: "Bearer"
        ))
        service.beforeRefreshReturns = { await barrier.pause() }
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: service,
            scope: try? keychain.loadSession()?.scope
        )
        let lookup = Task { await provider.getAccessToken() }
        await barrier.waitUntilPaused()
        await provider.revoke()
        try keychain.clearSession()
        await barrier.release()

        #expect(await lookup.value == nil)
        #expect(try keychain.loadTokens() == nil)
        #expect(try SharedTokenStore(keychain: sharedStore, lockPolicy: .processOnly).load() == nil)
        #expect(await provider.getAccessToken() == nil)
        #expect(service.refreshCallCount == 1)
    }

    @Test
    func aRevokedProviderCannotBePrimedWithNewTokens() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: AuthRefreshFixture(),
            scope: try? keychain.loadSession()?.scope
        )
        await provider.revoke()
        do {
            try await provider.storeSession(
                account: .fixture(),
                tokens: TokenPair(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: .distantFuture)
            )
            Issue.record("A revoked provider must reject priming")
        } catch is CancellationError {} catch { Issue.record("Expected lifetime cancellation") }
        #expect(try keychain.loadTokens() == nil)
    }

    @Test
    func aFreshLoginProviderCannotBorrowThePreviouslyStoredCredentials() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        try keychain.saveSession(account: .fixture(), tokens: TokenPair(
            accessToken: "previous-access", refreshToken: "previous-refresh", expiresAt: .distantFuture
        ))
        let service = AuthRefreshFixture()
        let provider = AppAuthTokenProvider(identityURL: identityURL, keychainStore: keychain, tokenService: service)
        #expect(await provider.getAccessToken() == nil)
        #expect(service.refreshCallCount == 0)
    }

    @Test(arguments: [false, true])
    func freshProviderCreatedBeforeLockOrLogoutCannotPrimeLateTokens(logout: Bool) async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let previous = try keychain.saveSession(account: .fixture(), tokens: TokenPair(
            accessToken: "previous-access", refreshToken: "previous-refresh", expiresAt: .distantFuture
        ))
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: AuthRefreshFixture(),
            freshLoginProof: try keychain.freshLoginCommitProof()
        )
        if logout { try keychain.clearSession() }
        else { try keychain.lockSession() }

        do {
            try await provider.storeSession(account: .fixture(), tokens: TokenPair(
                accessToken: "late-access", refreshToken: "late-refresh", expiresAt: .distantFuture
            ))
            Issue.record("An obsolete fresh login must not persist tokens")
        } catch is CancellationError {} catch { Issue.record("Expected commit-authority cancellation") }

        #expect(try keychain.loadSession()?.scope == (logout ? nil : previous.scope))
        #expect(await provider.getAccessToken() == nil)
    }

    @Test
    func aFreshProviderRequiresCapturedCommitAuthority() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: AuthRefreshFixture()
        )
        do {
            try await provider.storeSession(account: .fixture(), tokens: TokenPair(
                accessToken: "new-access", refreshToken: "new-refresh", expiresAt: .distantFuture
            ))
            Issue.record("A fresh provider cannot infer commit authority at the end of login")
        } catch is CancellationError {} catch { Issue.record("Expected missing-authority cancellation") }
        #expect(try keychain.loadSession() == nil)
    }

    @Test
    func returningProviderCannotReuseAuthorizationAcrossLockEvenWithTheSameScope() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let saved = try keychain.saveSession(account: .fixture(), tokens: TokenPair(
            accessToken: "saved-access", refreshToken: "saved-refresh", expiresAt: .distantFuture
        ))
        let old = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: AuthRefreshFixture(),
            scope: saved.scope
        )
        try keychain.lockSession()

        #expect(await old.getAccessToken() == nil)
        do {
            _ = try await old.validatedScope()
            Issue.record("The preceding unlock's epoch must stay revoked")
        } catch is CancellationError {} catch { Issue.record("Expected unlock-epoch cancellation") }
        let current = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: AuthRefreshFixture(),
            scope: saved.scope
        )
        #expect(await current.getAccessToken() == saved.tokens.accessToken)
        #expect(await old.getAccessToken() == nil)
    }

    @Test
    func lateRefreshCannotModifyALaterSignInEvenWithoutExplicitProviderRevocation() async throws {
        let keychain = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let old = try keychain.saveSession(account: .fixture(), tokens: TokenPair(
            accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantPast
        ))
        let barrier = RefreshBarrier()
        let service = AuthRefreshFixture()
        service.refreshOutcome = .success(RefreshedTokenPayload(
            accessToken: "late-access",
            refreshToken: "late-refresh",
            expiresIn: 3600,
            tokenType: "Bearer"
        ))
        service.beforeRefreshReturns = { await barrier.pause() }
        let provider = AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: keychain,
            tokenService: service,
            scope: old.scope
        )
        let lookup = Task { await provider.getAccessToken() }
        await barrier.waitUntilPaused()
        let next = try keychain.saveSession(account: .fixture(), tokens: TokenPair(
            accessToken: "new-login-access", refreshToken: "new-login-refresh", expiresAt: .distantFuture
        ))
        await barrier.release()
        #expect(await lookup.value == nil)
        #expect(try keychain.loadSession()?.scope == next.scope)
        #expect(try keychain.loadTokens() == next.tokens)
        #expect(await provider.getAccessToken() == nil)
    }

    private actor RefreshBarrier {
        private var paused = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                paused = true
                for waiter in waiters { waiter.resume() }
                waiters = []
            }
        }

        func waitUntilPaused() async {
            if paused { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() { continuation?.resume(); continuation = nil }
    }

    private actor ExpiryProbe {
        private var reported = false

        func record() { reported = true }
        func wasReported() -> Bool { reported }
    }
}
