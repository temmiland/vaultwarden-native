import Foundation
import SecurityStorage

/// Redacted recovery classification: a server rotation could not be retained in either store.
/// This reports cleanup failure, but is NOT a durable refresh-intent/recovery journal.
public enum TokenCommitRecoveryError: Error, Sendable, Equatable {
    case rotationNotDurable(capabilityRevocationFailed: Bool)
}

/// Data owns the one private/shared merge rule. Concrete shared record encoding, grant operations
/// and App Group composition are supplied through the synchronous transaction port.
public struct AppTokenPersistence: TokenPersistence {
    private let sessions: PrivateAuthSessionStore
    private let shared: any SharedTokenTransacting
    private let authorizationEpoch: UUID?

    public init(sessions: PrivateAuthSessionStore, shared: any SharedTokenTransacting, authorizationEpoch: UUID? = nil) {
        self.sessions = sessions
        self.shared = shared
        self.authorizationEpoch = authorizationEpoch
    }

    public func withRefreshLease<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await shared.withRefreshLease(operation)
    }

    public func beginRefresh(requiringScope scope: TokenScope, generation: UInt64) throws -> TokenRefreshIntent? {
        try shared.withTokenTransaction { transaction in
            guard let current = try reconcile(in: transaction, requiringScope: scope),
                  current.tokens.generation == generation else { return nil }
            return try transaction.beginRefresh(scope: scope, generation: generation)
        }
    }

    public func finishRefresh(_ intent: TokenRefreshIntent) throws {
        try shared.withTokenTransaction { try $0.finishRefresh(intent) }
    }

    public func isCurrentScope(_ scope: TokenScope) throws -> Bool {
        try shared.withTokenTransaction { transaction in
            try transaction.requireNoPendingCleanup()
            if let authorizationEpoch, try transaction.publicationEpoch() != authorizationEpoch { return false }
            return try sessions.load()?.scope == scope
        }
    }

    public func load(requiringScope scope: TokenScope) throws -> TokenPair? {
        try reconcile(requiringScope: scope)?.tokens
    }

    public func reconcile(requiringScope scope: TokenScope? = nil) throws -> PersistedAuthSession? {
        try shared.withTokenTransaction { try reconcile(in: $0, requiringScope: scope) }
    }

    /// For compound unlock publication/lock transitions already holding this same shared-store
    /// transaction. Never opens another lock. Ownership is checked BEFORE reading shared tokens.
    public func reconcile(
        in transaction: any SharedTokenTransactionPort,
        requiringScope scope: TokenScope? = nil
    ) throws -> PersistedAuthSession? {
        try transaction.requireNoPendingCleanup()
        if let authorizationEpoch, try transaction.publicationEpoch() != authorizationEpoch { return nil }
        guard let current = try sessions.load() else { return nil }
        if let scope, current.scope != scope { return nil }
        guard let winner = try transaction.eligibleTokens(requiringScope: current.scope),
              winner.generation > current.tokens.generation else { return current }
        let record = PersistedAuthSession(account: current.account, scope: current.scope, tokens: winner)
        try sessions.save(record)
        return record
    }

    public func commitRefresh(
        _ tokens: TokenPair,
        basedOnGeneration generation: UInt64,
        requiringScope scope: TokenScope
    ) throws -> TokenPair? {
        try shared.withTokenTransaction { transaction in
            guard let current = try reconcile(in: transaction, requiringScope: scope) else { return nil }
            if current.tokens.generation > generation { return current.tokens }
            guard current.tokens.generation == generation else { return nil }
            try transaction.validateRefreshCommit(scope: scope, generation: generation)
            guard generation < UInt64.max, tokens.generation == generation + 1 else {
                throw KeychainStoreError.decodeFailed
            }
            let replacement = PersistedAuthSession(account: current.account, scope: scope, tokens: tokens)
            // Validate BEFORE shared publication, not only after potentially corrupting shared data.
            try sessions.validate(replacement)
            var publicationError: Error?
            var published = false
            do {
                if let proof = try transaction.unlockProof(), proof.authenticationID == scope.authenticationID,
                   proof.account.userID == scope.account.userID,
                   proof.account.serverBaseURL == scope.account.serverBaseURL {
                    try transaction.publish(tokens, scope: scope)
                    published = true
                }
            } catch { publicationError = error }
            do { try sessions.save(replacement) }
            catch {
                if !published {
                    var revocationFailed = false
                    do { try transaction.revokeCapabilities() }
                    catch { revocationFailed = true }
                    throw TokenCommitRecoveryError.rotationNotDurable(capabilityRevocationFailed: revocationFailed)
                }
                // A successfully published shared rotation remains recoverable on the next read.
                throw error
            }
            if let publicationError {
                // Private storage retained the issued pair. Deny this lookup and independently
                // revoke the obsolete extension capability; cleanup failure must propagate.
                try transaction.revokeCapabilities()
                throw publicationError
            }
            return tokens
        }
    }

    /// Preserve a newer eligible extension rotation before lock. Capability removal is attempted
    /// independently even when reconciliation fails; it is never reported as successful on error.
    public func reconcileAndRevoke() throws {
        try shared.withTokenTransaction { transaction in
            var firstError: Error?
            do { _ = try reconcile(in: transaction) }
            catch { firstError = error }
            do { try transaction.revokeCapabilities() }
            catch { firstError = firstError ?? error }
            if let firstError { throw firstError }
        }
    }
}
