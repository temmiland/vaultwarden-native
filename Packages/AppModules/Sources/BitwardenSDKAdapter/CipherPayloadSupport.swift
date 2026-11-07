import Foundation

/// Detect unsupported wire shape without interpreting, copying or logging unknown values.
/// This is a write-safety boundary, NOT support for new fields or their access-policy semantics.
enum CipherPayloadSupport {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { nil }
    }

    private indirect enum Shape: Sendable {
        case object(Set<String>, [String: Shape])
        case array(Shape)
        /// A known future cipher slot may be empty on supported item types. Any actual payload
        /// remains unsupported and therefore read-only until the app can preserve it losslessly.
        case nullOnly

        func hasUnrecognizedFields(in decoder: any Decoder) throws -> Bool {
            switch self {
            case let .object(keys, children):
                let values = try decoder.container(keyedBy: Key.self)
                if values.allKeys.contains(where: { !keys.contains($0.stringValue) }) { return true }
                for (name, shape) in children {
                    let key = Key(name)
                    guard values.contains(key), try !values.decodeNil(forKey: key) else { continue }
                    if try shape.hasUnrecognizedFields(in: values.superDecoder(forKey: key)) { return true }
                }
                return false
            case let .array(element):
                var values = try decoder.unkeyedContainer()
                while !values.isAtEnd {
                    if try element.hasUnrecognizedFields(in: values.superDecoder()) { return true }
                }
                return false
            case .nullOnly:
                return try !decoder.singleValueContainer().decodeNil()
            }
        }
    }

    static func hasUnrecognizedFields(in decoder: any Decoder) throws -> Bool {
        try cipher.hasUnrecognizedFields(in: decoder) || hasConflictingLegacyURI(in: decoder)
    }

    /// Vaultwarden emits `login.uri` as a deprecated alias of `login.uris[0].uri`. It is safe to
    /// omit that alias only when its encrypted value exactly matches the canonical first URI.
    private static func hasConflictingLegacyURI(in decoder: any Decoder) throws -> Bool {
        let root = try decoder.container(keyedBy: Key.self)
        let loginKey = Key("login")
        guard root.contains(loginKey), try !root.decodeNil(forKey: loginKey) else { return false }
        let loginDecoder = try root.superDecoder(forKey: loginKey)
        let login = try loginDecoder.container(keyedBy: Key.self)
        let aliasKey = Key("uri")
        guard login.contains(aliasKey), try !login.decodeNil(forKey: aliasKey) else { return false }
        let alias = try login.decode(String.self, forKey: aliasKey)
        let urisKey = Key("uris")
        guard login.contains(urisKey), try !login.decodeNil(forKey: urisKey) else { return true }
        var uris = try login.nestedUnkeyedContainer(forKey: urisKey)
        guard !uris.isAtEnd else { return true }
        let first = try uris.superDecoder().container(keyedBy: Key.self)
        return try first.decodeIfPresent(String.self, forKey: aliasKey) != alias
    }

    private static func object(_ keys: [String], children: [String: Shape] = [:]) -> Shape {
        .object(Set(keys), children)
    }

    // `object` is an existing response discriminator only at these two response levels.
    private static let cipher: Shape = .object(Set(CipherResponseDTO.CodingKeys.allCases.map(\.rawValue)).union(
        ["object", "bankAccount", "driversLicense", "passport"]
    ), [
        "login": object([
            "username", "password", "passwordRevisionDate", "uris", "uri", "totp", "autofillOnPageLoad",
            "fido2Credentials",
        ], children: [
            "uris": .array(object(["uri", "uriChecksum", "match"])),
            "fido2Credentials": .array(object([
                "credentialId", "keyType", "keyAlgorithm", "keyCurve", "keyValue", "rpId", "rpName",
                "userHandle", "userName", "userDisplayName", "counter", "discoverable", "creationDate",
            ])),
        ]),
        "card": object(["cardholderName", "brand", "number", "expMonth", "expYear", "code"]),
        "identity": object([
            "title", "firstName", "middleName", "lastName", "address1", "address2", "address3", "city", "state",
            "postalCode", "country", "company", "email", "phone", "ssn", "username", "passportNumber", "licenseNumber",
        ]),
        "secureNote": object(["type"]),
        "sshKey": object(["privateKey", "publicKey", "keyFingerprint"]),
        "fields": .array(object(["type", "name", "value", "linkedId"])),
        "passwordHistory": .array(object(["password", "lastUsedDate"])),
        "permissions": object(["delete", "restore"]),
        "attachments": .array(object(["id", "url", "fileName", "key", "size", "sizeName", "object"])),
        // Vaultwarden 1.37.5 serializes these supported upstream cipher slots as null on
        // unrelated ciphers. Accept only that empty representation; real values stay fenced.
        "bankAccount": .nullOnly,
        "driversLicense": .nullOnly,
        "passport": .nullOnly,
    ])
}
