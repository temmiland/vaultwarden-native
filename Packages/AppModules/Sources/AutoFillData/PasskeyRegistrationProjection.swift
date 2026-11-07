import AutoFillContract
import BitwardenSDKAdapter
import Domain
import Foundation

public enum PasskeyRegistrationProjectionError: Error, Sendable, Equatable {
    case invalidIdentity, identityCleanupFailed
}

/// Cache first, then incrementally publish only the confirmed new passkey. The durable write
/// journal is owned by the caller and is never erased here, even if both projections succeed.
public actor PasskeyRegistrationProjection {
    private let cache: LegacyAutoFillCacheStore
    private let proof: ExtensionUnlockProof
    private let originalRevision: UUID
    private let identities: any PasskeyIdentityUpdating
    private let identityMutations: any CredentialIdentityMutationCoordinating
    private let checkAccess: @Sendable () throws -> Void
    private var isProjecting = false

    public init(
        cache: LegacyAutoFillCacheStore,
        proof: ExtensionUnlockProof,
        cacheRevision: UUID,
        identities: any PasskeyIdentityUpdating,
        identityMutations: any CredentialIdentityMutationCoordinating,
        checkAccess: @escaping @Sendable () throws -> Void
    ) {
        self.cache = cache; self.proof = proof; originalRevision = cacheRevision
        self.identities = identities; self.checkAccess = checkAccess
        self.identityMutations = identityMutations
    }

    public func project(
        _ cipher: CipherResponseDTO,
        credentialID: Foundation.Data,
        relyingPartyIdentifier: String,
        makeIdentity: @Sendable (CipherResponseDTO) async throws -> CredentialIdentityDescriptor
    ) async throws {
        guard !isProjecting else { throw AutoFillOperationError.operationInProgress }
        isProjecting = true
        defer { isProjecting = false }
        try checkAccess()
        let receipt = try cache.upsertReturningReceipt(
            cipher,
            for: proof.account,
            requiringProof: proof,
            cacheRevision: originalRevision
        )
        try requireCurrent(receipt)
        let identity = try await makeIdentity(cipher)
        try requireCurrent(receipt)
        guard identity.kind == .passkey, !identity.id.isEmpty, !credentialID.isEmpty,
              !relyingPartyIdentifier.isEmpty, identity.credentialID == credentialID,
              identity.serviceIdentifier == relyingPartyIdentifier, identity.recordIdentifier.rawValue == cipher.id,
              identity.userHandle != nil, let userName = identity.user ?? identity.label, !userName.isEmpty else {
            throw PasskeyRegistrationProjectionError.invalidIdentity
        }
        try await identityMutations.withExclusiveMutation {
            try await self.publish(identity, requiring: receipt)
        }
    }

    private func publish(_ identity: CredentialIdentityDescriptor, requiring receipt: AutoFillCacheCommitReceipt) async throws {
        // Recheck after waiting for app replace/clear, before any OS call. Hold the same batch
        // through compensation so it cannot remove an identity a later sync just published.
        try requireCurrent(receipt)
        do {
            try await identities.addPasskeyIdentity(identity)
            try requireCurrent(receipt)
        } catch {
            let projectionError = error
            do { try await identities.removePasskeyIdentity(identity) }
            catch { throw PasskeyRegistrationProjectionError.identityCleanupFailed }
            throw projectionError
        }
    }

    private func requireCurrent(_ receipt: AutoFillCacheCommitReceipt) throws {
        try checkAccess()
        try cache.requireCurrent(receipt, requiring: proof)
        try checkAccess()
    }
}
