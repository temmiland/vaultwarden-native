import AutoFillContract
@testable import Data
import Foundation
import Networking
import SecurityStorage
import Testing

@Suite
struct SharedTokenStoreTests {
    @Test
    func cacheMutationPortRunsOnlyWithTheExactUnlockAndBoundTokens() throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(SharedTokens(accessToken: "test-access", refreshToken: "test-refresh", expiresAt: .distantFuture))
        let proof = try bindTokensForTesting(keychain: keychain, store: store)
        let authorization: any AutoFillCacheMutationAuthorizing = store
        var writes = 0
        let result = try authorization.withAuthorizedCacheMutation(requiring: proof) { writes += 1; return 42 }
        #expect(result == 42)
        let anotherUnlock = ExtensionUnlockProof(account: proof.account, authenticationID: proof.authenticationID)
        #expect(throws: CancellationError.self) {
            try authorization.withAuthorizedCacheMutation(requiring: anotherUnlock) { writes += 1 }
        }
        try store.clear()
        #expect(throws: CancellationError.self) {
            try authorization.withAuthorizedCacheMutation(requiring: proof) { writes += 1 }
        }
        #expect(writes == 1)
    }

    @Test
    func revokedGrantCannotAuthorizeACacheMutationEvenIfTokensRemain() throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(SharedTokens(accessToken: "test-access", refreshToken: "test-refresh", expiresAt: .distantFuture))
        let proof = try bindTokensForTesting(keychain: keychain, store: store)
        try SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly).revoke()
        var didWrite = false
        #expect(throws: CancellationError.self) {
            try store.withAuthorizedCacheMutation(requiring: proof) { didWrite = true }
        }
        #expect(!didWrite)
        #expect(try store.load() != nil)
    }

    @Test
    func lateExtensionRefreshCannotOverwriteTokensFromAReunlockWithTheSameGeneration() async throws {
        let keychain = InMemoryKeychain()
        let grantStore = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        let authenticationID = UUID()
        let scope = TokenScope(
            account: TokenAccountIdentity(userID: "account-1", serverBaseURL: URL(string: "https://vault.example.com")!),
            authenticationID: authenticationID
        )
        let info = SharedAccountInfo(
            userId: "account-1",
            email: "test@example.com",
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedPrivateKey: "fake-wrapped-key",
            serverBaseURL: URL(string: "https://vault.example.com")!
        )
        try grantStore.save(
            userKey: "fake-test-key",
            accountInfo: info,
            authenticationID: authenticationID,
            ifRevocationEpochIs: grantStore.publicationEpoch()
        )
        let oldProof = try #require(try grantStore.load()?.proof)
        let tokens = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try tokens.save(
            SharedTokens(
                accessToken: "old-token",
                refreshToken: "old-refresh",
                expiresAt: .distantPast,
                generation: 7,
                scope: scope,
                unlockID: oldProof.unlockID
            )
        )
        let barrier = UnlockRefreshBarrier()
        let provider = SharedTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            store: tokens,
            httpClient: PausedRefreshClient(barrier: barrier),
            unlockProof: oldProof
        )
        let lookup = Task { await provider.getAccessToken() }
        await barrier.waitUntilPaused()
        try grantStore.revoke()
        try grantStore.save(
            userKey: "fake-test-key",
            accountInfo: info,
            authenticationID: authenticationID,
            ifRevocationEpochIs: grantStore.publicationEpoch()
        )
        // Generations alone cannot distinguish this from the old refresh's starting point.
        try tokens.save(SharedTokens(
            accessToken: "reunlock-token",
            refreshToken: "reunlock-refresh",
            expiresAt: .distantFuture,
            generation: 7,
            scope: scope,
            unlockID: try grantStore.load()?.proof.unlockID
        ))
        await barrier.release()
        #expect(await lookup.value == nil)
        #expect(try tokens.load()?.accessToken == "reunlock-token")
        #expect(try tokens.load()?.generation == 7)
    }

    private func bindTokensForTesting(keychain: InMemoryKeychain, store: SharedTokenStore) throws -> ExtensionUnlockProof {
        let scope = TokenScope(
            account: TokenAccountIdentity(userID: "account-1", serverBaseURL: URL(string: "https://vault.example.com")!)
        )
        let grants = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        let info = SharedAccountInfo(
            userId: "account-1",
            email: "test@example.com",
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedPrivateKey: "fake-key",
            serverBaseURL: scope.account.serverBaseURL
        )
        try grants.save(
            userKey: "fake-test-key",
            accountInfo: info,
            authenticationID: scope.authenticationID,
            ifRevocationEpochIs: grants.publicationEpoch()
        )
        let proof = try #require(try grants.load()?.proof)
        if let tokens = try store.load() {
            try store.save(SharedTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: tokens.expiresAt,
                generation: tokens.generation,
                updatedAt: tokens.updatedAt,
                scope: scope,
                unlockID: proof.unlockID
            ))
        }
        return proof
    }

    private actor UnlockRefreshBarrier {
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

    private struct PausedRefreshClient: HTTPClient {
        let barrier: UnlockRefreshBarrier
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            await barrier.pause() // deliberately ignores cancellation
            return HTTPResponse(statusCode: 200, headers: [:], body: Data(
                #"{"access_token":"late-token","refresh_token":"late-refresh","expires_in":3600}"#.utf8
            ))
        }

        func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse { throw CancellationError(
        ) }
        func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse { throw CancellationError(
        ) }
    }

    private final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
        private var storage: [String: Data] = [:]
        private(set) var protections: [String: SecurityStorage.KeychainProtection] = [:]

        func write(_ value: Data, for account: String, protection: SecurityStorage.KeychainProtection) throws {
            storage[account] = value
            protections[account] = protection
        }

        func read(_ account: String) throws -> Data {
            guard let value = storage[account] else { throw KeychainStoreError.notFound }
            return value
        }

        func remove(_ account: String) throws { storage.removeValue(forKey: account) }
    }

    private struct StubHTTPClient: HTTPClient {
        let statusCode: Int
        let body: Data
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            HTTPResponse(statusCode: statusCode, headers: [:], body: body)
        }

        func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
            try await send(request)
        }

        func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
            let response = try await send(request)
            try response.requireSuccess()
            try response.body.write(to: destinationURL)
            return HTTPFileResponse(statusCode: response.statusCode, headers: response.headers)
        }
    }

    private struct FailingHTTPClient: HTTPClient {
        struct Offline: Error {}
        func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw Offline() }
        func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse { throw Offline() }
        func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse { throw Offline() }
    }

    @Test
    func tokensRoundTrip() throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        let tokens = SharedTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)

        try store.save(tokens)

        #expect(try store.load() == tokens)
    }

    @Test
    func missingProductionContainerDoesNotRunAnOperation() throws {
        var ran = false
        #expect(throws: SharedTokenStoreLockError.missingContainer) {
            try SharedTokenStoreLock.withExclusiveLock(containerURL: nil) { ran = true }
        }
        #expect(!ran)
        try SharedTokenStoreLock.withExclusiveLock(containerURL: nil, policy: .processOnly) { ran = true }
        #expect(ran)
    }

    @Test
    func anEscapedTransactionCannotReadOrMutateOutsideTheLock() throws {
        let store = SharedTokenStore(keychain: InMemoryKeychain(), lockPolicy: .processOnly)
        let escaped = try store.withTransaction { $0 }
        #expect(throws: CancellationError.self) { try escaped.load() }
        #expect(throws: CancellationError.self) { try escaped.clear() }
    }

    @Test
    func theDataPortKeepsTheSameRevocableTransactionLease() throws {
        let store = SharedTokenStore(keychain: InMemoryKeychain(), lockPolicy: .processOnly)
        let escaped = try store.withTokenTransaction { $0 }
        #expect(throws: CancellationError.self) { try escaped.unlockProof() }
        #expect(throws: CancellationError.self) { try escaped.revokeCapabilities() }
    }

    @Test
    func theDataPortReturnsPairsOnlyForTheExactProofAndSignInScope() throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(SharedTokens(accessToken: "test-access", refreshToken: "test-refresh", expiresAt: .distantFuture))
        let proof = try bindTokensForTesting(keychain: keychain, store: store)
        let scope = try #require(try store.load()?.scope)
        try store.withTokenTransaction { transaction in
            let tokens = try transaction.tokens(requiringProof: proof)
            let eligible = try transaction.eligibleTokens(requiringScope: scope)
            #expect(tokens?.accessToken == "test-access")
            #expect(eligible?.refreshToken == "test-refresh")
            let otherLogin = TokenScope(account: scope.account)
            let wrongLogin = try transaction.eligibleTokens(requiringScope: otherLogin)
            #expect(wrongLogin == nil)
            let otherUnlock = ExtensionUnlockProof(account: proof.account, authenticationID: scope.authenticationID)
            let wrongUnlock = try transaction.tokens(requiringProof: otherUnlock)
            #expect(wrongUnlock == nil)
            let replaced = try transaction.replace(
                TokenPair(
                    accessToken: "test-wrong",
                    refreshToken: "test-wrong-refresh",
                    expiresAt: .distantFuture,
                    generation: 2
                ),
                basedOnGeneration: 1,
                requiringScope: otherLogin,
                requiringProof: proof
            )
            #expect(!replaced)
        }
        #expect(try store.load()?.generation == 1)
    }

    @Test
    func unboundLegacyTokensNeverAuthorizeTheCurrentGrant() async throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        let proof = try bindTokensForTesting(keychain: keychain, store: store)
        try store.save(SharedTokens(accessToken: "legacy", refreshToken: "legacy-refresh", expiresAt: .distantFuture))
        #expect(try store.load(requiringUnlockProof: proof) == nil)
        let provider = SharedTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            store: store,
            httpClient: FailingHTTPClient(),
            unlockProof: proof
        )
        #expect(await provider.getAccessToken() == nil)
    }

    @Test
    func legacyTokenPayloadDecodesAtGenerationZero() throws {
        let legacyJSON = #"{"accessToken":"access","refreshToken":"refresh","expiresAt":1234567890}"#

        let decoded = try JSONDecoder().decode(SharedTokens.self, from: Data(legacyJSON.utf8))

        #expect(decoded.generation == 0)
        #expect(decoded.updatedAt == decoded.expiresAt)
    }

    @Test
    func conditionalReplacementNeverOverwritesANewerGeneration() throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(
            SharedTokens(accessToken: "current", refreshToken: "r2", expiresAt: .distantFuture, generation: 2)
        )

        let replaced = try store.replace(
            SharedTokens(accessToken: "stale", refreshToken: "r1", expiresAt: .distantFuture, generation: 2),
            ifCurrentGenerationIs: 1
        )

        #expect(replaced == false)
        #expect(try store.load()?.accessToken == "current")
        #expect(try store.load()?.generation == 2)
    }

    @Test
    func clearRemovesThem() throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(SharedTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture))

        try store.clear()

        #expect(try store.load() == nil)
    }

    @Test
    func lockAcquisitionFailureDoesNotRunTheProtectedOperation() throws {
        let invalidContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultwarden-lock-test-\(UUID().uuidString)", isDirectory: false)
        try Data().write(to: invalidContainer)
        defer { try? FileManager.default.removeItem(at: invalidContainer) }
        var operationRan = false

        var lockFailed = false
        do {
            try SharedTokenStoreLock.withExclusiveLock(containerURL: invalidContainer) {
                operationRan = true
            }
        } catch is SharedTokenStoreLockError {
            lockFailed = true
        }

        #expect(lockFailed)
        #expect(!operationRan)
    }

    /// Tokens let the extension act as the user, so they must never sit in the Keychain at a
    /// weaker protection class than the vault key they accompany.
    @Test
    func tokensAreStoredNoWeakerThanWhenUnlocked() throws {
        let keychain = InMemoryKeychain()
        try SharedTokenStore(keychain: keychain, lockPolicy: .processOnly).save(
            SharedTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
        )

        #expect(keychain.protections[AutoFillStorageKeys.sharedTokensAccount] == .whenUnlocked)
    }

    @Test
    func aTokenIsTreatedAsExpiredShortlyBeforeItActuallyIs() {
        let almostExpired = SharedTokens(
            accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(10)
        )
        let comfortable = SharedTokens(
            accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(600)
        )

        // Refreshing early avoids racing a request that's mid-flight as the token lapses.
        #expect(almostExpired.isExpired)
        #expect(comfortable.isExpired == false)
    }

    @Test
    func refreshGrantUsesTheSharedConnectorClientIdentifier() {
        let body = OAuthClientConfiguration.refreshGrantBody(refreshToken: "refresh token")
        let fields = Dictionary(uniqueKeysWithValues: String(decoding: body, as: UTF8.self)
            .split(separator: "&")
            .compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            })

        #expect(OAuthClientConfiguration.clientID == "connector")
        #expect(fields["client_id"] == "connector")
    }

    @Test
    func aValidTokenIsReturnedWithoutTouchingTheNetwork() async throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(SharedTokens(accessToken: "still-good", refreshToken: "r", expiresAt: .distantFuture))

        let provider = SharedTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            store: store,
            httpClient: FailingHTTPClient(), unlockProof: try bindTokensForTesting(keychain: keychain, store: store)
        )

        #expect(await provider.getAccessToken() == "still-good")
    }

    @Test
    func anExpiredTokenIsRefreshedAndThePairIsPersisted() async throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        let initial = SharedTokens(accessToken: "old", refreshToken: "r0", expiresAt: .distantPast)
        try store.save(initial)

        let body = Data(#"{"access_token":"fresh","refresh_token":"r1","expires_in":3600}"#.utf8)
        let provider = SharedTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            store: store,
            httpClient: StubHTTPClient(statusCode: 200, body: body),
            unlockProof: try bindTokensForTesting(keychain: keychain, store: store)
        )

        #expect(await provider.getAccessToken() == "fresh")
        // The rotated refresh token has to be kept, or the next refresh fails.
        #expect(try store.load()?.refreshToken == "r1")
        #expect(try store.load()?.generation == initial.generation + 1)
    }

    /// Vaultwarden doesn't always rotate the refresh token; dropping it in that case would break
    /// the next refresh.
    @Test
    func anUnrotatedRefreshTokenIsRetained() async throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(SharedTokens(accessToken: "old", refreshToken: "keep-me", expiresAt: .distantPast))

        let body = Data(#"{"access_token":"fresh","expires_in":3600}"#.utf8)
        let provider = SharedTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            store: store,
            httpClient: StubHTTPClient(statusCode: 200, body: body),
            unlockProof: try bindTokensForTesting(keychain: keychain, store: store)
        )

        _ = await provider.getAccessToken()

        #expect(try store.load()?.refreshToken == "keep-me")
    }

    @Test
    func noTokenIsProducedWhenNoneWereShared() async {
        let provider = SharedTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            store: SharedTokenStore(keychain: InMemoryKeychain(), lockPolicy: .processOnly),
            httpClient: FailingHTTPClient(),
            unlockProof: ExtensionUnlockProof(
                account: AutoFillAccountIdentity(
                    userID: "missing",
                    serverBaseURL: URL(string: "https://vault.example.com")!
                )
            )
        )

        #expect(await provider.getAccessToken() == nil)
    }

    @Test
    func aRejectedRefreshYieldsNoToken() async throws {
        let keychain = InMemoryKeychain()
        let store = SharedTokenStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(SharedTokens(accessToken: "old", refreshToken: "revoked", expiresAt: .distantPast))

        let provider = SharedTokenProvider(
            identityURL: URL(string: "https://vault.example.com/identity")!,
            store: store,
            httpClient: StubHTTPClient(statusCode: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)),
            unlockProof: try bindTokensForTesting(keychain: keychain, store: store)
        )

        #expect(await provider.getAccessToken() == nil)
    }
}
