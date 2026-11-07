import AutoFillContract
import Domain
import Foundation

public protocol VaultRegistrationRecovery: Sendable {
    /// Return true while a mutation is unresolved. Only a full authoritative sync whose cache
    /// and OS identities were both published can permit removal of a matching journal record.
    func reconcile(identities: [CredentialIdentityDescriptor], canResolve: Bool) async throws -> Bool
    func reconcile(
        identities: [CredentialIdentityDescriptor],
        canResolve: Bool,
        passwordCiphertextHashes: [CipherID: Foundation.Data]
    ) async throws -> Bool
    func prepareReview(vaultRevision: UInt64) async throws -> PasskeyRegistrationRecoveryReview
    func abandon(_ review: PasskeyRegistrationRecoveryReview) async throws -> Bool
}

public extension VaultRegistrationRecovery {
    func reconcile(
        identities: [CredentialIdentityDescriptor],
        canResolve: Bool,
        passwordCiphertextHashes _: [CipherID: Foundation.Data]
    ) async throws -> Bool {
        try await reconcile(identities: identities, canResolve: canResolve)
    }

    func prepareReview(vaultRevision _: UInt64) async throws -> PasskeyRegistrationRecoveryReview { throw PasskeyRegistrationReviewError.unavailable }
    func abandon(_: PasskeyRegistrationRecoveryReview) async throws -> Bool { throw PasskeyRegistrationReviewError.unavailable }
}

public actor PasskeyRegistrationRecoveryReconciler: VaultRegistrationRecovery {
    private let journal: any PasskeyRegistrationRecoveryStoring
    private let proof: ExtensionUnlockProof
    private let checkAccess: @Sendable () throws -> Void
    private var pendingReview: (review: PasskeyRegistrationRecoveryReview, record: PasskeyRegistrationRecoveryRecord)?
    public init(
        journal: any PasskeyRegistrationRecoveryStoring,
        proof: ExtensionUnlockProof,
        checkAccess: @escaping @Sendable () throws -> Void
    ) {
        self.journal = journal; self.proof = proof; self.checkAccess = checkAccess
    }

    public func reconcile(identities: [CredentialIdentityDescriptor], canResolve: Bool) async throws -> Bool {
        try await reconcile(
            identities: identities,
            canResolve: canResolve,
            passwordCiphertextHashes: [:]
        )
    }

    public func reconcile(
        identities: [CredentialIdentityDescriptor],
        canResolve: Bool,
        passwordCiphertextHashes: [CipherID: Foundation.Data]
    ) async throws -> Bool {
        try checkAccess()
        pendingReview = nil
        let records = try journal.records(requiring: proof)
        guard canResolve else { return !records.isEmpty }
        let resolved = records.filter { record in
            if record.kind == .password {
                // Only an authoritative sync can resolve the exact server-confirmed ID.
                // Strict URI modes need not publish an OS identity to prove the saved login.
                guard record.phase == .confirmed, let id = record.serverCipherID,
                      let expected = record.passwordCiphertextHash, expected.count == 32 else { return false }
                return passwordCiphertextHashes[CipherID(rawValue: id)] == expected
            }
            let matching = identities.filter { identity in
                let expectedCipherID = record.serverCipherID ?? record.targetCipherID
                return identity.kind == .passkey && identity.credentialID == record.credentialID &&
                    identity.serviceIdentifier == record.relyingPartyIdentifier &&
                    (expectedCipherID == nil || expectedCipherID == identity.recordIdentifier.rawValue)
            }
            return matching.count == 1
        }
        try checkAccess()
        try journal.remove(Set(resolved.map(\.mutationID)), requiring: proof)
        try checkAccess()
        return !(try journal.records(requiring: proof)).isEmpty
    }

    public func prepareReview(vaultRevision: UInt64) async throws -> PasskeyRegistrationRecoveryReview {
        try checkAccess()
        pendingReview = nil
        let records = try journal.records(requiring: proof)
        guard records.count == 1, let record = records.first else { throw PasskeyRegistrationReviewError.unavailable }
        let readiness: PasskeyRecoveryReviewReadiness = record.originatingUnlockID == nil ? .legacyOriginUnknown :
            (record.originatingUnlockID == proof.unlockID ? .requiresFreshUnlock : .ready)
        let review = PasskeyRegistrationRecoveryReview(
            vaultRevision: vaultRevision,
            relyingPartyIdentifier: record.relyingPartyIdentifier,
            serverConfirmed: record.phase == .confirmed,
            readiness: readiness
        )
        try checkAccess()
        pendingReview = (review, record)
        return review
    }

    public func abandon(_ review: PasskeyRegistrationRecoveryReview) async throws -> Bool {
        try checkAccess()
        guard let pendingReview, pendingReview.review == review else { throw PasskeyRegistrationReviewError.reviewChanged }
        guard review.readiness != .requiresFreshUnlock else { throw PasskeyRegistrationReviewError.freshUnlockRequired }
        guard review.readiness != .legacyOriginUnknown else { throw PasskeyRegistrationReviewError.legacyOriginUnknown }
        self.pendingReview = nil // one-shot even on failure: reread/review rather than reuse consent
        let remaining: Bool
        do { remaining = try journal.abandonReviewedRecord(pendingReview.record, requiring: proof) }
        catch PasskeyRegistrationRecoveryError.reviewChanged { throw PasskeyRegistrationReviewError.reviewChanged }
        catch PasskeyRegistrationRecoveryError.freshUnlockRequired { throw PasskeyRegistrationReviewError.freshUnlockRequired }
        catch PasskeyRegistrationRecoveryError.legacyOriginUnknown { throw PasskeyRegistrationReviewError.legacyOriginUnknown }
        try checkAccess()
        return remaining
    }
}
