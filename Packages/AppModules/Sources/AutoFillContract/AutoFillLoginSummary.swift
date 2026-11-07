import Foundation

/// Picker metadata only. Passwords, TOTP seeds and passkey private keys never enter UI lists.
public struct AutoFillLoginSummary: Identifiable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public struct ID: Hashable, Sendable {
        public let cipherId: String
        public let credentialID: Foundation.Data?
    }

    public var id: ID { ID(cipherId: cipherId, credentialID: fido2CredentialId) }
    public struct StoredURI: Sendable, Equatable {
        public let value: String
        public let matchType: AutoFillURIMatchMode?
        public init(value: String, matchType: AutoFillURIMatchMode?) { self.value = value; self.matchType = matchType }
    }

    public let cipherId: String
    public let name: String
    public let username: String?
    public let hasTOTP: Bool
    public let uris: [StoredURI]
    public let fido2CredentialId: Foundation.Data?
    public let fido2UserHandle: Foundation.Data?

    public init(
        cipherId: String,
        name: String,
        username: String?,
        hasTOTP: Bool = false,
        uris: [StoredURI] = [],
        fido2CredentialId: Foundation.Data? = nil,
        fido2UserHandle: Foundation.Data? = nil
    ) {
        self.cipherId = cipherId; self.name = name; self.username = username; self.hasTOTP = hasTOTP
        self.uris = uris; self.fido2CredentialId = fido2CredentialId; self.fido2UserHandle = fido2UserHandle
    }

    public var description: String { "AutoFillLoginSummary(<redacted>)" }
    public var debugDescription: String { description }
}
