import AutoFillContract
import Foundation

/// Applied INSIDE the shared identity batch. Publication additionally reads cache/grant under
/// the token lock; clear needs no live runtime, but an older unlock must not clear a newer one.
public enum AutoFillIdentityMutationPolicy {
    public static func requirePublication(cache: SharedVaultCacheData, proof: ExtensionUnlockProof, revision: UInt64) throws {
        try cache.validate(for: proof.account)
        guard cache.projectionRevision == revision else { throw CancellationError() }
    }

    public static func requireClear(capturedProof: ExtensionUnlockProof?, currentProof: ExtensionUnlockProof?) throws {
        guard currentProof == nil || currentProof == capturedProof else { throw CancellationError() }
    }
}
