import BitwardenSdk
import Foundation

public enum SDKAutoFillFidoError: Error, Sendable, Equatable {
    case accessDenied, saveUnavailable, ambiguousSelection, invalidRequest
}

/// Encrypted SDK backing never escapes as a raw Cipher through the AutoFill/extension ports.
public struct SDKAutoFillEncryptedCipher: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let value: Cipher
    let encryptedFor: String
    public init(legacyCipher: Cipher, encryptedFor: String) {
        value = legacyCipher; self.encryptedFor = encryptedFor
    }

    public var id: String? { value.id }
    public var allowsPasskeyRegistration: Bool {
        SDKVaultAccessPolicy.allowsUnpromptedSecretAccess(value) && value.edit && value.type == .login && value.login != nil
    }

    public var description: String { "SDKAutoFillEncryptedCipher(<redacted>)" }
    public var debugDescription: String { description }
}

public struct SDKAutoFillRegistrationResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let credentialID: Foundation.Data
    public let attestationObject: Foundation.Data
    public init(credentialID: Foundation.Data, attestationObject: Foundation.Data) {
        self.credentialID = credentialID; self.attestationObject = attestationObject
    }

    public var description: String { "SDKAutoFillRegistrationResult(<redacted>)" }
    public var debugDescription: String { description }
}

public struct SDKAutoFillAssertionResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let credentialID: Foundation.Data
    public let userHandle: Foundation.Data
    public let signature: Foundation.Data
    public let authenticatorData: Foundation.Data
    public var description: String { "SDKAutoFillAssertionResult(<redacted>)" }
    public var debugDescription: String { description }
}

public enum SDKPasskeyRegistrationMutationValidator {
    public static func addedCredential(
        target: SDKAutoFillCredentialView,
        encrypted: SDKAutoFillEncryptedCipher,
        updated: SDKAutoFillCredentialView,
        previous: [SDKAutoFillPasskeyMetadata],
        current: [SDKAutoFillPasskeyMetadata],
        relyingPartyIdentifier: String
    ) throws -> SDKAutoFillPasskeyMetadata {
        guard target.allowsPasskeyRegistration, encrypted.allowsPasskeyRegistration, updated.allowsPasskeyRegistration,
              target.id == encrypted.id, target.id == updated.id, updated.hasPasskeys, !relyingPartyIdentifier.isEmpty,
              target.id == nil || (previous + current).allSatisfy({ $0.cipherId == target.id }) else {
            throw SDKAutoFillFidoError.accessDenied
        }
        let previousIDs = Set(previous.map(\.credentialId)), currentIDs = Set(current.map(\.credentialId))
        let added = current.filter { !previousIDs.contains($0.credentialId) }
        guard previousIDs.count == previous.count, currentIDs.count == current.count,
              previousIDs.isSubset(of: currentIDs), added.count == 1, let credential = added.first,
              !credential.credentialId.isEmpty, credential.rpId == relyingPartyIdentifier else {
            throw SDKAutoFillFidoError.accessDenied
        }
        return credential
    }
}
