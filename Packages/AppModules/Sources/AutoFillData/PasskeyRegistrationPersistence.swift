import AutoFillContract
import BitwardenSDKAdapter
import Foundation

/// Typed registration crypto/HTTP port. Access to the original cache is distinct from proof-only
/// access because a confirmed write's own projection advances that original cache UUID.
public protocol PasskeyRegistrationSource: Sendable {
    func checkAccess() throws
    func requireOriginalAccess(to target: SDKAutoFillCredentialView) throws
    func metadata(in view: SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata]
    func decrypt(_ cipher: SDKAutoFillEncryptedCipher) async throws -> SDKAutoFillCredentialView
    func save(_ cipher: SDKAutoFillEncryptedCipher) async throws -> CipherResponseDTO
}

public struct LivePasskeyRegistrationSource: PasskeyRegistrationSource {
    private let session: ExtensionVaultSession
    private let service: SDKCipherService
    public init(session: ExtensionVaultSession, service: SDKCipherService) { self.session = session; self.service = service }
    public func checkAccess() throws { try session.checkAccess() }
    public func requireOriginalAccess(to target: SDKAutoFillCredentialView) throws {
        _ = try session.readCache()
        if target.id != nil { try session.requireCurrentAccess(to: target, forEditing: true) }
    }

    public func metadata(in view: SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata] {
        try session.perform { try $0.passkeyMetadata(in: view) }
    }

    public func decrypt(_ cipher: SDKAutoFillEncryptedCipher) async throws -> SDKAutoFillCredentialView {
        try await session.perform { try await $0.decryptView(cipher) }
    }

    public func save(_ cipher: SDKAutoFillEncryptedCipher) async throws -> CipherResponseDTO { try await service.savePasskeyResponse(
        cipher
    ) }
}

/// Owns the former extension server-writer sequencing. The SDK selects decoded bytes/policy;
/// the existing mutation actor owns reservation, HTTP classification and async projection.
public struct PasskeyRegistrationPersistence: Sendable {
    private let source: any PasskeyRegistrationSource
    private let target: SDKAutoFillCredentialView
    private let relyingPartyIdentifier: String
    private let proof: ExtensionUnlockProof
    private let writer: PasskeyRegistrationWriter
    private let journal: any PasskeyRegistrationRecoveryStoring
    private let project: @Sendable (CipherResponseDTO, Foundation.Data, String) async throws -> Void

    public init(
        source: any PasskeyRegistrationSource,
        target: SDKAutoFillCredentialView,
        relyingPartyIdentifier: String,
        proof: ExtensionUnlockProof,
        writer: PasskeyRegistrationWriter,
        journal: any PasskeyRegistrationRecoveryStoring,
        project: @escaping @Sendable (CipherResponseDTO, Foundation.Data, String) async throws -> Void
    ) {
        self.source = source; self.target = target; self.relyingPartyIdentifier = relyingPartyIdentifier
        self.proof = proof; self.writer = writer; self.journal = journal; self.project = project
    }

    public func save(_ cipher: SDKAutoFillEncryptedCipher) async throws -> PasskeyRegistrationReceipt {
        try source.requireOriginalAccess(to: target)
        guard target.allowsPasskeyRegistration, cipher.allowsPasskeyRegistration, cipher.id == target.id else {
            throw AutoFillOperationError.accessDenied
        }
        let previous = try source.metadata(in: target)
        let updated = try await source.decrypt(cipher)
        try source.requireOriginalAccess(to: target)
        let current = try source.metadata(in: updated)
        let credential = try SDKPasskeyRegistrationMutationValidator.addedCredential(
            target: target,
            encrypted: cipher,
            updated: updated,
            previous: previous,
            current: current,
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let record = PasskeyRegistrationRecoveryRecord(
            account: proof.account,
            credentialID: credential.credentialId,
            relyingPartyIdentifier: relyingPartyIdentifier,
            targetCipherID: target.id,
            originatingUnlockID: proof.unlockID
        )
        return try await writer.save(
            record: record,
            proof: proof,
            journal: journal,
            checkAccess: { try source.checkAccess() },
            write: { try source.requireOriginalAccess(to: target); return try await source.save(cipher) },
            project: { try await project($0, record.credentialID, record.relyingPartyIdentifier) }
        )
    }
}
