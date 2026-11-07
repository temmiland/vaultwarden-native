import CryptoKit
import Foundation

public enum PasswordSaveFingerprint {
    /// Hash randomized ciphertext, never a plaintext password or password verifier.
    public static func make(ciphertext: String) -> Data { Data(SHA256.hash(data: Data(ciphertext.utf8))) }
}

/// Public selection/ownership metadata only. Never stores a key, seed, attestation or HTTP body.
public struct PasskeyRegistrationRecoveryRecord: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Phase: String, Codable, Sendable { case submitted, confirmed }
    public enum Kind: String, Codable, Sendable { case password }
    /// Absent in existing journals, which contain passkey registrations only.
    public let kind: Kind?
    public let passwordCiphertextHash: Data?
    public let mutationID: UUID
    public let account: AutoFillAccountIdentity
    public let credentialID: Data
    public let relyingPartyIdentifier: String
    public let targetCipherID: String?
    public var serverCipherID: String?
    public var phase: Phase
    /// Additive v1 metadata. Missing on old journals: never infer an originating unlock.
    public var originatingUnlockID: UUID?

    public init(
        mutationID: UUID = UUID(),
        account: AutoFillAccountIdentity,
        credentialID: Data,
        relyingPartyIdentifier: String,
        targetCipherID: String?,
        originatingUnlockID: UUID? = nil,
        kind: Kind? = nil,
        passwordCiphertextHash: Data? = nil
    ) {
        self.mutationID = mutationID; self.account = account; self.credentialID = credentialID
        self.relyingPartyIdentifier = relyingPartyIdentifier; self.targetCipherID = targetCipherID
        phase = .submitted
        self.originatingUnlockID = originatingUnlockID
        self.kind = kind
        self.passwordCiphertextHash = passwordCiphertextHash
    }

    public var description: String { "PasskeyRegistrationRecoveryRecord(<redacted>)" }
    public var debugDescription: String { description }
    public func validate() throws {
        guard !account.userID.isEmpty, kind == .password ? credentialID.isEmpty : !credentialID.isEmpty, !relyingPartyIdentifier.isEmpty,
              kind != .password || passwordCiphertextHash?.count == 32,
              targetCipherID?.isEmpty != true, serverCipherID?.isEmpty != true,
              phase != .submitted || serverCipherID == nil,
              targetCipherID == nil || serverCipherID == nil || targetCipherID == serverCipherID else {
            throw PasskeyRegistrationRecoveryError.invalidRecord
        }
    }
}

public enum PasskeyRegistrationRecoveryError: Error, Sendable, Equatable {
    case pendingMutation, invalidRecord, unsupportedSchema, missingMutation, containerUnavailable
    case reviewChanged, freshUnlockRequired, legacyOriginUnknown
}

/// Each transaction must hold the shared grant/token process lock, including the journal read.
public protocol PasskeyRegistrationRecoveryStoring: Sendable {
    func records(requiring proof: ExtensionUnlockProof) throws -> [PasskeyRegistrationRecoveryRecord]
    func reserve(_ record: PasskeyRegistrationRecoveryRecord, requiring proof: ExtensionUnlockProof) throws
    func confirm(_ mutationID: UUID, serverCipherID: String?, requiring proof: ExtensionUnlockProof) throws
    func remove(_ mutationIDs: Set<UUID>, requiring proof: ExtensionUnlockProof) throws
    /// Compare the entire reviewed record and remove it in ONE shared authorization transaction.
    /// Requires an originating unlock different from the currently authorized unlock.
    func abandonReviewedRecord(_ expected: PasskeyRegistrationRecoveryRecord, requiring proof: ExtensionUnlockProof) throws -> Bool
}

public extension PasskeyRegistrationRecoveryStoring {
    func abandonReviewedRecord(_: PasskeyRegistrationRecoveryRecord, requiring _: ExtensionUnlockProof) throws -> Bool {
        throw PasskeyRegistrationRecoveryError.legacyOriginUnknown
    }
}
