import AutoFillContract
import Foundation
import SecurityStorage

/// One fixed invocation proof; no refresh algorithm or legacy store models. The concrete shared
/// transaction validates proof AND pair ownership under the process lock for every read/write.
public struct ExtensionTokenPersistence: TokenPersistence {
    private let shared: any SharedTokenTransacting
    private let proof: ExtensionUnlockProof

    public init(shared: any SharedTokenTransacting, proof: ExtensionUnlockProof) {
        self.shared = shared
        self.proof = proof
    }

    public func withRefreshLease<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await shared.withRefreshLease(operation)
    }

    public func beginRefresh(requiringScope scope: TokenScope, generation: UInt64) throws -> TokenRefreshIntent? {
        guard matches(scope) else { return nil }
        return try shared.withTokenTransaction { transaction in
            try transaction.requireNoPendingCleanup()
            guard let current = try transaction.tokens(requiringProof: proof), current.generation == generation else { return nil }
            return try transaction.beginRefresh(scope: scope, generation: generation)
        }
    }

    public func finishRefresh(_ intent: TokenRefreshIntent) throws {
        try shared.withTokenTransaction { try $0.finishRefresh(intent) }
    }

    private func matches(_ scope: TokenScope) -> Bool {
        scope.authenticationID == proof.authenticationID && scope.account.userID == proof.account.userID &&
            scope.account.serverBaseURL == proof.account.serverBaseURL
    }

    public func isCurrentScope(_ scope: TokenScope) throws -> Bool {
        guard matches(scope) else { return false }
        return try shared.withTokenTransaction { try $0.unlockProof() == proof }
    }

    public func load(requiringScope scope: TokenScope) throws -> TokenPair? {
        guard matches(scope) else { return nil }
        return try shared.withTokenTransaction { try $0.tokens(requiringProof: proof) }
    }

    public func commitRefresh(
        _ tokens: TokenPair,
        basedOnGeneration generation: UInt64,
        requiringScope scope: TokenScope
    ) throws -> TokenPair? {
        guard matches(scope), generation < UInt64.max, tokens.generation == generation + 1 else { return nil }
        guard !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty,
              tokens.expiresAt.timeIntervalSinceReferenceDate.isFinite,
              tokens.updatedAt.timeIntervalSinceReferenceDate.isFinite else { throw KeychainStoreError.decodeFailed }
        return try shared.withTokenTransaction { transaction in
            guard let current = try transaction.tokens(requiringProof: proof) else { return nil }
            if current.generation > generation { return current }
            try transaction.validateRefreshCommit(scope: scope, generation: generation)
            guard current.generation == generation,
                  try transaction.replace(
                      tokens,
                      basedOnGeneration: generation,
                      requiringScope: scope,
                      requiringProof: proof
                  ) else { return nil }
            return try transaction.tokens(requiringProof: proof)
        }
    }
}
