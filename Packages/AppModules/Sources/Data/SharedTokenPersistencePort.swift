import AutoFillContract
import Foundation

/// A synchronous, non-Sendable lease valid ONLY inside its store's transaction callback. Concrete
/// adapters must invalidate escaped leases, enforce exact scope/proof and distinguish read failure
/// from absence. Values crossing this boundary have no legacy storage/SDK payloads.
public protocol SharedTokenTransactionPort: AnyObject {
    func requireNoPendingCleanup() throws
    func publicationEpoch() throws -> UUID
    func beginRefresh(scope: TokenScope, generation: UInt64) throws -> TokenRefreshIntent
    func finishRefresh(_ intent: TokenRefreshIntent) throws
    func validateRefreshCommit(scope: TokenScope, generation: UInt64) throws
    func unlockProof() throws -> ExtensionUnlockProof?
    func eligibleTokens(requiringScope scope: TokenScope) throws -> TokenPair?
    func tokens(requiringProof proof: ExtensionUnlockProof) throws -> TokenPair?
    func publish(_ tokens: TokenPair, scope: TokenScope) throws
    func replace(
        _ tokens: TokenPair,
        basedOnGeneration generation: UInt64,
        requiringScope scope: TokenScope,
        requiringProof proof: ExtensionUnlockProof
    ) throws -> Bool
    func revokeCapabilities() throws
}

/// Private/shared compare-and-write must participate in this SAME critical section. No await,
/// network, SDK, biometric operation or nested transaction belongs inside the callback.
public protocol SharedTokenTransacting: Sendable {
    func withTokenTransaction<T>(_ operation: (any SharedTokenTransactionPort) throws -> T) throws -> T
    /// A different file lock spans the network request. Short storage transactions remain
    /// available for lock/logout and must never wait for this lease while holding their lock.
    func withRefreshLease<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T
}
