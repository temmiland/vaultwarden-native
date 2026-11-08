import AutoFillContract
import Foundation
import Networking
import SecurityStorage

/// The OAuth token pair, in the form the AutoFill extension needs it.
///
/// Transitional shared representation around Data's token values. Tokens carry both the durable
/// sign-in scope and the current unlock ID; a matching generation alone never authorizes access.
public struct SharedTokens: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    /// Cross-process revision of this token pair. The app imports a shared record only when this
    /// value is strictly newer than its private record.
    public let generation: UInt64
    public let updatedAt: Date
    public let scope: TokenScope?
    public let unlockID: UUID?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        generation: UInt64 = 1,
        updatedAt: Date = Date(),
        scope: TokenScope? = nil,
        unlockID: UUID? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.generation = generation
        self.updatedAt = updatedAt
        self.scope = scope
        self.unlockID = unlockID
    }

    /// Legacy payloads remain decodable for inspection/recovery, but cannot authorize token
    /// access or be adopted by the app: their missing ownership must not be inferred.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        generation = try container.decodeIfPresent(UInt64.self, forKey: .generation) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? expiresAt
        scope = try container.decodeIfPresent(TokenScope.self, forKey: .scope)
        unlockID = try container.decodeIfPresent(UUID.self, forKey: .unlockID)
    }

    public var isExpired: Bool {
        // Refresh a little early to avoid racing a request that's mid-flight when the token expires.
        Date() >= expiresAt.addingTimeInterval(-30)
    }

    public var description: String { "SharedTokens(<redacted>)" }
    public var debugDescription: String { description }
}

/// Reads and writes the token pair shared with the AutoFill extension.
///
/// **Why the extension gets tokens at all:** saving a passkey means writing a cipher to the server,
/// and there is no offline path that doesn't risk losing a credential the relying party already
/// considers registered. The extension already holds the decrypted vault key, so it can already
/// read everything; adding tokens lets it also *write*, which is a real but incremental widening.
///
/// Consequently these are cleared on lock as well as logout, exactly like the shared vault key -
/// a locked vault must not leave a process able to act as the user (see `AuthCredentialStore`).
public struct SharedTokenStore: SharedTokenTransacting, AutoFillCacheMutationAuthorizing {
    private let keychain: any SecurityStorage.KeychainStoring
    private let lockPolicy: SharedStoreLockPolicy
    private let containerURL: URL?

    public init(
        keychain: any SecurityStorage.KeychainStoring,
        containerURL: URL? = nil,
        lockPolicy: SharedStoreLockPolicy = .appGroup
    ) {
        self.keychain = keychain
        self.lockPolicy = lockPolicy
        self.containerURL = containerURL
    }

    public func load(requiringUnlockProof proof: ExtensionUnlockProof? = nil) throws -> SharedTokens? {
        try withTransaction { transaction in
            if let proof { return try transaction.authorizedTokens(for: proof) }
            return try transaction.load()
        }
    }

    public func save(_ tokens: SharedTokens) throws {
        try withTransaction { transaction in
            try transaction.save(tokens)
        }
    }

    /// Replaces a record only if the exact generation used for a refresh is still current. The
    /// Keychain item itself is updated as one value, so readers never observe a half-written token
    /// pair. A caller that loses the race must reload rather than overwrite a newer refresh token.
    @discardableResult
    public func replace(
        _ replacement: SharedTokens,
        ifCurrentGenerationIs expectedGeneration: UInt64,
        requiringUnlockProof proof: ExtensionUnlockProof? = nil
    ) throws -> Bool {
        try withTransaction { transaction in
            try transaction.replace(
                replacement,
                ifCurrentGenerationIs: expectedGeneration,
                requiringUnlockProof: proof
            )
        }
    }

    public func clear() throws {
        try withTransaction { transaction in try transaction.clear() }
    }

    /// Synchronous ONLY: no SDK/network/biometric work while holding this lock. Private app
    /// persistence participates here so adoption + revocation cannot lose an intervening refresh.
    public func withTransaction<T>(_ operation: (SharedTokenTransaction) throws -> T) throws -> T {
        try SharedTokenStoreLock.withExclusiveLock(containerURL: containerURL, policy: lockPolicy) {
            let transaction = SharedTokenTransaction(
                keychain: keychain,
                containerURL: containerURL,
                lockPolicy: lockPolicy
            )
            defer { transaction.invalidate() }
            return try operation(transaction)
        }
    }

    public func withTokenTransaction<T>(_ operation: (any SharedTokenTransactionPort) throws -> T) throws -> T {
        try withTransaction { try operation($0) }
    }

    public func withRefreshLease<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        // processOnly is an explicit fixture mode, never a live missing-container fallback.
        if lockPolicy == .processOnly { return try await operation() }
        return try await AsyncCrossProcessFileLock(
            containerURL: containerURL,
            filename: ".vaultwarden-refresh.lock"
        ).withExclusiveLock(operation)
    }

    public func withAuthorizedCacheMutation<Value>(
        requiring proof: ExtensionUnlockProof,
        _ operation: () throws -> Value
    ) throws -> Value {
        try withTransaction { transaction in
            guard try transaction.authorizedTokens(for: proof) != nil else { throw CancellationError() }
            return try operation()
        }
    }
}

/// Non-Sendable, revocable lease: an escaped transaction cannot bypass the process lock later.
public final class SharedTokenTransaction: SharedTokenTransactionPort {
    private let keychain: any SecurityStorage.KeychainStoring
    private var isActive = true
    private let containerURL: URL?
    private let lockPolicy: SharedStoreLockPolicy
    private var unlockStore: SharedAutoFillUnlockStore {
        SharedAutoFillUnlockStore(keychain: keychain, containerURL: containerURL, lockPolicy: lockPolicy)
    }

    fileprivate init(
        keychain: any SecurityStorage.KeychainStoring,
        containerURL: URL?,
        lockPolicy: SharedStoreLockPolicy
    ) {
        self.keychain = keychain
        self.containerURL = containerURL
        self.lockPolicy = lockPolicy
    }

    fileprivate func invalidate() { isActive = false }
    private func checkActive() throws { guard isActive else { throw CancellationError() } }

    func cleanupIntent() throws -> AuthCleanupIntent? {
        try checkActive()
        return try AuthCleanupIntent.read(from: keychain)
    }

    func beginCleanup(_ kind: AuthCleanupIntent.Kind) throws {
        try checkActive()
        let current = try cleanupIntent()
        if current?.kind == .logout, kind == .lock { throw AuthCleanupRecoveryError.pending }
        if current?.kind != kind {
            try keychain.write(JSONEncoder().encode(AuthCleanupIntent(kind)), for: AuthCleanupIntent.key)
        }
    }

    func finishCleanup() throws {
        try checkActive()
        try keychain.remove(AuthCleanupIntent.key)
    }

    func requireNoCleanup() throws {
        try checkActive()
        try AuthCleanupIntent.requireNone(in: keychain)
    }

    public func requireNoPendingCleanup() throws { try requireNoCleanup() }

    public func load() throws -> SharedTokens? {
        try checkActive()
        let data: Foundation.Data
        do { data = try keychain.read(AutoFillStorageKeys.sharedTokensAccount) }
        catch SecurityStorage.KeychainStoreError.notFound { return nil }
        do { return try JSONDecoder().decode(SharedTokens.self, from: data) }
        catch { throw SecurityStorage.KeychainStoreError.decodeFailed }
    }

    public func unlockProof() throws -> ExtensionUnlockProof? {
        try checkActive()
        return try unlockStore.loadUnderExistingLock()?.proof
    }

    /// Fresh sign-in compares its captured epoch inside this same transaction, not by recursively
    /// taking the process lock or checking a value before the commit's lock is held.
    public func publicationEpoch() throws -> UUID {
        try checkActive()
        return try unlockStore.publicationEpochUnderExistingLock()
    }

    public func beginRefresh(scope: TokenScope, generation: UInt64) throws -> TokenRefreshIntent {
        try checkActive()
        try requireNoCleanup()
        let previous: TokenRefreshIntent?
        do { previous = try TokenRefreshIntent.read(from: keychain) }
        catch KeychainStoreError.decodeFailed { throw TokenRefreshRecoveryError.unconfirmedRotation }
        if let previous, previous.scope == scope {
            guard previous.generation < generation else { throw TokenRefreshRecoveryError.unconfirmedRotation }
        }
        let intent = TokenRefreshIntent(scope: scope, generation: generation, publicationEpoch: try publicationEpoch())
        try keychain.write(JSONEncoder().encode(intent), for: TokenRefreshIntent.key)
        return intent
    }

    public func finishRefresh(_ intent: TokenRefreshIntent) throws {
        try checkActive()
        guard try TokenRefreshIntent.read(from: keychain) == intent else { return }
        try keychain.remove(TokenRefreshIntent.key)
    }

    public func validateRefreshCommit(scope: TokenScope, generation: UInt64) throws {
        try checkActive()
        try requireNoCleanup()
        if let intent = try TokenRefreshIntent.read(from: keychain), intent.scope == scope,
           intent.generation == generation {
            guard try publicationEpoch() == intent.publicationEpoch else { throw CancellationError() }
        }
    }

    func clearRefreshIntent() throws {
        try checkActive()
        try keychain.remove(TokenRefreshIntent.key)
    }

    private func matches(_ tokens: SharedTokens, proof: ExtensionUnlockProof) -> Bool {
        guard let scope = tokens.scope, let authenticationID = proof.authenticationID else { return false }
        return scope.authenticationID == authenticationID && tokens.unlockID == proof.unlockID &&
            scope.account.userID == proof.account.userID &&
            scope.account.serverBaseURL == proof.account.serverBaseURL &&
            !tokens.accessToken.isEmpty && !tokens.refreshToken.isEmpty && tokens.generation > 0 &&
            tokens.expiresAt.timeIntervalSinceReferenceDate.isFinite && tokens.updatedAt.timeIntervalSinceReferenceDate.isFinite
    }

    public func authorizedTokens(for proof: ExtensionUnlockProof) throws -> SharedTokens? {
        guard try unlockProof() == proof, let tokens = try load(), matches(tokens, proof: proof) else { return nil }
        return tokens
    }

    public func tokensForReconciliation(scope: TokenScope) throws -> SharedTokens? {
        guard let proof = try unlockProof(), let tokens = try authorizedTokens(for: proof),
              tokens.scope == scope else { return nil }
        return tokens
    }

    // The Data port exposes only scoped token pairs, never the legacy/unbound storage envelope.
    public func eligibleTokens(requiringScope scope: TokenScope) throws -> TokenPair? {
        try tokensForReconciliation(scope: scope).map(pair)
    }

    public func tokens(requiringProof proof: ExtensionUnlockProof) throws -> TokenPair? {
        try authorizedTokens(for: proof).map(pair)
    }

    public func replace(
        _ tokens: TokenPair,
        basedOnGeneration generation: UInt64,
        requiringScope scope: TokenScope,
        requiringProof proof: ExtensionUnlockProof
    ) throws -> Bool {
        try checkActive()
        guard scope.authenticationID == proof.authenticationID, scope.account.userID == proof.account.userID,
              scope.account.serverBaseURL == proof.account.serverBaseURL else { return false }
        return try replace(
            SharedTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: tokens.expiresAt,
                generation: tokens.generation,
                updatedAt: tokens.updatedAt,
                scope: scope,
                unlockID: proof.unlockID
            ),
            ifCurrentGenerationIs: generation,
            requiringUnlockProof: proof
        )
    }

    private func pair(_ tokens: SharedTokens) -> TokenPair {
        TokenPair(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            generation: tokens.generation,
            updatedAt: tokens.updatedAt
        )
    }

    /// Unbound records remain writable solely for legacy-data fixtures; they cannot authorize an
    /// extension or be reconciled. Bound records require the exact currently persisted grant.
    public func save(_ tokens: SharedTokens) throws {
        try checkActive()
        if tokens.scope != nil || tokens.unlockID != nil {
            guard let proof = try unlockProof(), matches(tokens, proof: proof) else { throw CancellationError() }
        }
        try keychain.write(JSONEncoder().encode(tokens), for: AutoFillStorageKeys.sharedTokensAccount)
    }

    public func replace(
        _ replacement: SharedTokens,
        ifCurrentGenerationIs expected: UInt64,
        requiringUnlockProof proof: ExtensionUnlockProof? = nil
    ) throws -> Bool {
        try checkActive()
        if let proof, try authorizedTokens(for: proof) == nil { return false }
        guard let current = try load(), current.generation == expected,
              replacement.generation > expected, replacement.scope == current.scope,
              replacement.unlockID == current.unlockID else { return false }
        try save(replacement)
        return true
    }

    public func publish(_ tokens: TokenPair, scope: TokenScope) throws {
        guard let proof = try unlockProof(), proof.authenticationID == scope.authenticationID,
              proof.account.userID == scope.account.userID,
              proof.account.serverBaseURL == scope.account.serverBaseURL else { throw CancellationError() }
        if let current = try tokensForReconciliation(scope: scope) {
            guard current.generation <= tokens.generation else { throw CancellationError() }
            if current.generation == tokens.generation {
                guard current.accessToken == tokens.accessToken, current.refreshToken == tokens.refreshToken,
                      current.expiresAt == tokens.expiresAt else { throw SecurityStorage.KeychainStoreError.decodeFailed }
                return
            }
        }
        try save(SharedTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            generation: tokens.generation,
            updatedAt: tokens.updatedAt,
            scope: scope,
            unlockID: proof.unlockID
        ))
    }

    public func saveUnlock(
        userKey: String,
        accountInfo: SharedAccountInfo,
        scope: TokenScope,
        publicationEpoch: UUID
    ) throws {
        try checkActive()
        guard scope.account.userID == accountInfo.userId,
              scope.account.serverBaseURL == accountInfo.serverBaseURL else { throw CancellationError() }
        try unlockStore.saveUnderExistingLock(
            userKey: userKey,
            accountInfo: accountInfo,
            authenticationID: scope.authenticationID,
            ifRevocationEpochIs: publicationEpoch
        )
    }

    public func clear() throws {
        try checkActive()
        var firstError: Error?
        for account in [AutoFillStorageKeys.sharedTokensAccount, AutoFillStorageKeys.legacySharedTokensAccount] {
            do { try keychain.remove(account) }
            catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    public func revokeCapabilities() throws {
        try checkActive()
        var firstError: Error?
        do { try unlockStore.revokeUnderExistingLock() }
        catch { firstError = error }
        do { try clear() } catch { firstError = firstError ?? error }
        if let firstError { throw firstError }
    }
}

/// Serializes token compare-and-write AND unlock-grant/epoch transitions across app and extension. A
/// Keychain value write is atomic, but a read/compare/write sequence is not; the zero-byte lock
/// file supplies that missing process boundary. The file lives only in the App Group container and
/// contains no credential material. Fixtures must explicitly choose a process-only lock; live
/// operations fail closed if the App Group container is unavailable.
public enum SharedStoreLockPolicy: Sendable {
    /// Live default. Missing entitlements/container must never silently remove serialization.
    case appGroup
    /// Explicitly injected in-memory fixtures only, never used by app composition.
    case processOnly
}

typealias SharedTokenStoreLockError = CrossProcessFileLockError

enum SharedTokenStoreLock {
    static func withExclusiveLock<T>(
        containerURL: URL? = nil,
        policy: SharedStoreLockPolicy = .appGroup,
        _ operation: () throws -> T
    ) throws -> T {
        // SecurityStorage owns the lock implementation; composition injects the container. Keep the
        // existing filename so new/old processes still serialize on the same physical file.
        let lock = CrossProcessFileLock(
            containerURL: containerURL,
            filename: ".vaultwarden-token-store.lock",
            policy: policy == .processOnly ? .processOnly : .requiredContainer
        )
        return try lock.withExclusiveLock(operation)
    }
}

/// Compatibility shell around the same Data coordinator used by the app. It has no independent
/// refresh/HTTP/expiry algorithm and can never acquire another invocation's unlock proof.
public struct SharedTokenProvider: Sendable {
    private let coordinator: TokenCoordinator?

    public init(
        identityURL: URL,
        store: SharedTokenStore,
        httpClient: HTTPClient,
        unlockProof: ExtensionUnlockProof
    ) {
        if let authenticationID = unlockProof.authenticationID {
            let scope = TokenScope(
                account: TokenAccountIdentity(
                    userID: unlockProof.account.userID,
                    serverBaseURL: unlockProof.account.serverBaseURL
                ),
                authenticationID: authenticationID
            )
            coordinator = TokenCoordinator(
                scope: scope,
                identityURL: identityURL,
                persistence: ExtensionTokenPersistence(shared: store, proof: unlockProof),
                refreshService: DefaultTokenRefreshService(httpClient: httpClient)
            )
        } else { coordinator = nil }
    }

    public func getAccessToken() async -> String? { await coordinator?.getAccessToken() }
    public func requireAccessToken() async throws -> String {
        guard let coordinator else { throw CancellationError() }
        return try await coordinator.requireAccessToken()
    }

    public func revoke() async { await coordinator?.revoke() }
}
