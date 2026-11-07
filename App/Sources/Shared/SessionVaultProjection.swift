import AutoFillContract
import AutoFillData
import Data
import Foundation
import PlatformServices

/// App and extension file writes take the SAME process lock as shared-grant revocation. The
/// fixed proof prevents an old session from overwriting or removing a newer session's cache.
private struct AuthorizedProjectionFileStore: AutoFillProjectionFileStore {
    let base: AtomicAutoFillProjectionFileStore
    let proof: ExtensionUnlockProof?
    let checkAccess: @Sendable () throws -> Void

    func readProjection() throws -> Foundation.Data? {
        try SharedAppGroup.makeTokenStore().withTransaction { transaction in
            try validate(transaction); return try base.readProjection()
        }
    }

    func replaceProjectionAtomically(with data: Foundation.Data) throws {
        try SharedAppGroup.makeTokenStore().withTransaction { transaction in
            try checkAccess(); try validate(transaction)
            // Cross-process mutations may have advanced the projection since our last write.
            let proposed = try JSONDecoder().decode(SharedVaultCacheData.self, from: data)
            if let current = try base.readProjection(),
               let existing = try? JSONDecoder().decode(SharedVaultCacheData.self, from: current),
               existing.owner == proposed.owner,
               (existing.projectionRevision ?? 0) >= (proposed.projectionRevision ?? 0) {
                throw CancellationError()
            }
            try base.replaceProjectionAtomically(with: data)
        }
    }

    func removeProjection() throws {
        try SharedAppGroup.makeTokenStore().withTransaction { transaction in
            // Revocation already makes the old file unusable. Never delete a newer unlock's data.
            guard let proof, try transaction.unlockProof() == proof else { return }
            do { try base.removeProjection() }
            catch {
                try transaction.revokeCapabilities()
                throw error
            }
        }
    }

    private func validate(_ transaction: SharedTokenTransaction) throws {
        guard let proof, try transaction.authorizedTokens(for: proof) != nil else { throw CancellationError() }
    }
}

struct SessionVaultProjection {
    let initialRevision: UInt64
    let writer: AutoFillProjectionWriter?
    let identityPublisher: CredentialIdentityPublisher
    var registrationRecovery: (any VaultRegistrationRecovery)? = nil

    static func make(session: AuthenticatedSession) -> SessionVaultProjection {
        let container = SharedAppGroup.containerURL
        let identityMutations = SharedAppGroup.identityMutationCoordinator(containerURL: container)
        guard let container else {
            // No uncoordinated fallback: suggestions may need repair, but cannot be cleared
            // out of order with another entitled process. Missing grants still deny fulfilment.
            return SessionVaultProjection(
                initialRevision: 0,
                writer: nil,
                identityPublisher: CredentialIdentityPublisher(
                    store: SystemCredentialIdentityStore(),
                    identityMutations: identityMutations,
                    checkProjection: { _ in throw CancellationError() },
                    checkClearAccess: { throw CancellationError() }
                )
            )
        }
        let owner = AutoFillAccountIdentity(
            userID: session.storageAccount.userID,
            serverBaseURL: session.storageAccount.serverBaseURL
        )
        let candidate = try? SharedAppGroup.makeUnlockStore().load()?.proof
        let proof = candidate?.account == owner ? candidate : nil
        let files = AuthorizedProjectionFileStore(
            base: AtomicAutoFillProjectionFileStore(directoryURL: container, fileName: "autofill-cache.json"),
            proof: proof, checkAccess: { try session.checkAccess() }
        )
        let codec = LegacyAutoFillCacheCodec(owner: owner)
        let initial = (try? files.readProjection().map { try codec.decode($0).revision }) ?? 0
        let publisher = CredentialIdentityPublisher(
            store: SystemCredentialIdentityStore(),
            identityMutations: identityMutations,
            checkProjection: { revision in
                try session.checkAccess()
                guard let proof, let bytes = try files.readProjection() else { throw CancellationError(
                ) }
                try AutoFillIdentityMutationPolicy.requirePublication(
                    cache: JSONDecoder().decode(
                        SharedVaultCacheData.self,
                        from: bytes
                    ),
                    proof: proof,
                    revision: revision
                )
                try session.checkAccess()
            },
            checkClearAccess: {
                try SharedAppGroup.makeTokenStore().withTransaction { transaction in
                    try AutoFillIdentityMutationPolicy.requireClear(
                        capturedProof: proof,
                        currentProof: transaction.unlockProof()
                    )
                }
            }
        )
        let recovery = proof.map { proof in
            PasskeyRegistrationRecoveryReconciler(
                journal: PasskeyRegistrationRecoveryStore(
                    directoryURL: container,
                    authorization: SessionProjectionAuthorization(
                        proof: proof,
                        checkAccess: { try session.checkAccess() }
                    )
                ),
                proof: proof,
                checkAccess: { try session.checkAccess() }
            )
        }
        return SessionVaultProjection(
            initialRevision: initial,
            writer: AutoFillProjectionWriter(accountID: owner.userID, fileStore: files, encoding: codec),
            identityPublisher: publisher,
            registrationRecovery: recovery
        )
    }
}

private struct SessionProjectionAuthorization: AutoFillCacheMutationAuthorizing {
    let proof: ExtensionUnlockProof
    let checkAccess: @Sendable () throws -> Void
    func withAuthorizedCacheMutation<Value>(requiring expected: ExtensionUnlockProof, _ operation: () throws -> Value) throws -> Value {
        try checkAccess()
        guard expected == proof else { throw CancellationError() }
        return try SharedAppGroup.makeTokenStore().withAuthorizedCacheMutation(requiring: expected) {
            try checkAccess(); return try operation()
        }
    }
}
