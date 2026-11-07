/// Serializes complete OS-index mutation batches across the app and extension. An incremental
/// add, its post-write authorization check and any compensation belong to ONE batch. The live
/// adapter must not silently fall back to process-only ordering if shared coordination fails.
public protocol CredentialIdentityMutationCoordinating: Sendable {
    func withExclusiveMutation(_ operation: @escaping @Sendable () async throws -> Void) async throws
}
