import AutoFillContract
import BitwardenSdk
import Foundation

/// Adapter-owned backing for one decrypted item. Data sees typed fields/policy, not SDK enums.
/// Raw views remain inside the adapter, including its FIDO callbacks and registration policy.
public struct SDKAutoFillCredentialView: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public struct URI: Sendable {
        public let value: String
        public let matchType: AutoFillURIMatchMode?
    }

    public struct Login: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        public let username: String?
        public let password: String?
        public let totp: String?
        public let uris: [URI]
        public var description: String { "SDKAutoFillLogin(<redacted>)" }
        public var debugDescription: String { description }
    }

    private let value: CipherView
    private let supportsLosslessEditing: Bool
    public init(legacyView: CipherView, supportsLosslessEditing: Bool = true) {
        value = legacyView
        self.supportsLosslessEditing = supportsLosslessEditing
    }

    var legacyView: CipherView { value }
    public var id: String? { value.id }
    public var name: String { value.name }
    public var edit: Bool { value.edit && supportsLosslessEditing }
    public var allowsPasskeyRegistration: Bool {
        allowsPasswordSaving
    }

    public var allowsPasswordSaving: Bool {
        SDKVaultAccessPolicy.allowsUnpromptedSecretAccess(value) && edit && value.type == .login && value.login != nil
    }

    public var hasPasskeys: Bool { !(value.login?.fido2Credentials ?? []).isEmpty }
    public var login: Login? {
        value.login.map { login in Login(
            username: login.username,
            password: login.password,
            totp: login.totp,
            uris: (login.uris ?? []).compactMap { uri in
                uri.uri.map { URI(
                    value: $0,
                    matchType: uri.match.map { AutoFillURIMatchMode(sdkMode: $0) }
                ) }
            }
        ) }
    }

    public func isCurrent(in ciphers: [CipherResponseDTO]) -> Bool {
        SDKVaultAccessPolicy.isCurrentAutoFillItem(value, in: ciphers)
    }

    public func isCurrent(matching cipher: CipherResponseDTO) -> Bool {
        SDKVaultAccessPolicy.isCurrentAutoFillItem(value, matching: cipher)
    }

    public var description: String { "SDKAutoFillCredentialView(<redacted>)" }
    public var debugDescription: String { description }
}

public struct SDKAutoFillPasskeyMetadata: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let credentialId: Foundation.Data
    public let cipherId: String
    public let rpId: String
    public let userNameForUi: String?
    public let userHandle: Foundation.Data
    public var description: String { "SDKAutoFillPasskeyMetadata(<redacted>)" }
    public var debugDescription: String { description }
    public init(legacyView: Fido2CredentialAutofillView) {
        credentialId = legacyView.credentialId; cipherId = legacyView.cipherId; rpId = legacyView.rpId
        userNameForUi = legacyView.userNameForUi; userHandle = legacyView.userHandle
    }
}
