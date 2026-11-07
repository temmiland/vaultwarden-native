import Foundation

/// A cache mutation must hold the same cross-process lock as shared-grant revocation and token
/// refresh. Implementations reread and validate the exact unlock proof and its token authority
/// while holding that lock, then invoke this synchronous, nonescaping operation inside it.
/// No SDK, network, biometric or async operation belongs in this critical section.
public protocol AutoFillCacheMutationAuthorizing: Sendable {
    func withAuthorizedCacheMutation<Value>(
        requiring proof: ExtensionUnlockProof,
        _ operation: () throws -> Value
    ) throws -> Value
}
