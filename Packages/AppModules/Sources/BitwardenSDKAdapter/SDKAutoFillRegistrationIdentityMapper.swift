import Domain
import Foundation

public enum SDKAutoFillRegistrationIdentityError: Error, Sendable, Equatable {
    case invalidMetadata
}

/// Select metadata using SDK-decoded bytes, never another interpretation of a stored ID string.
/// This source intentionally contains no password/TOTP/URI identities for incremental publication.
public enum SDKAutoFillRegistrationIdentityMapper {
    public static func source(
        cipher: CipherResponseDTO,
        view: SDKAutoFillCredentialView,
        passkeys: [SDKAutoFillPasskeyMetadata],
        credentialID: Foundation.Data,
        relyingPartyIdentifier: String
    ) throws -> VaultLoginIdentitySource {
        guard let id = cipher.id, !id.isEmpty, view.isCurrent(in: [cipher]), view.edit,
              SDKVaultAccessPolicy.allowsUnpromptedSecretAccess(view.legacyView),
              !credentialID.isEmpty, !relyingPartyIdentifier.isEmpty,
              Set(passkeys.map(\.credentialId)).count == passkeys.count else { throw SDKAutoFillRegistrationIdentityError.invalidMetadata }
        let matches = passkeys.filter { $0.credentialId == credentialID }
        guard matches.count == 1, let passkey = matches.first, passkey.cipherId == id,
              passkey.rpId == relyingPartyIdentifier else { throw SDKAutoFillRegistrationIdentityError.invalidMetadata }
        return VaultLoginIdentitySource(
            cipherID: CipherID(rawValue: id),
            displayName: view.name,
            username: view.login?.username,
            serviceIdentifiers: [],
            hasOneTimeCode: false,
            passkeys: [PasskeyIdentitySource(
                relyingPartyIdentifier: passkey.rpId,
                userName: passkey.userNameForUi,
                credentialID: passkey.credentialId,
                userHandle: passkey.userHandle
            )],
            isEligibleForAutoFill: true
        )
    }
}
