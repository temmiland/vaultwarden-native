import AutoFillContract
import Domain
import Foundation

/// A permanently revocable invocation lease, not a login/unlock implementation. The injected
/// reader must reread the shared capability, never return an in-memory authorization snapshot.
public final class ExtensionSession: Sendable {
    public let proof: ExtensionUnlockProof
    private let resource: any SessionResource
    private let currentProof: @Sendable () throws -> ExtensionUnlockProof?

    public init(
        proof: ExtensionUnlockProof,
        resource: any SessionResource,
        currentProof: @escaping @Sendable () throws -> ExtensionUnlockProof?
    ) {
        self.proof = proof
        self.resource = resource
        self.currentProof = currentProof
    }

    public func checkAccess() throws {
        do {
            try Task.checkCancellation()
            guard resource.isActive, try currentProof() == proof else { throw CancellationError() }
            // A concurrent local cancellation/revocation must not reopen the resource.
            guard resource.isActive else { throw CancellationError() }
        } catch {
            resource.revoke()
            throw error
        }
    }

    public func revoke() { resource.revoke() }
}
