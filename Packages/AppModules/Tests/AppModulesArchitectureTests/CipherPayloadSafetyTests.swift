import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct CipherPayloadSafetyTests {
    // Fabricated ciphertext/metadata. Include every supported nested object and two array rows
    // so the guard cannot accidentally inspect only the first URI, field or passkey.
    private let payload = """
    {
      "object":"cipherDetails", "id":"cipher-1", "type":1, "name":"enc-name", "edit":true,
      "revisionDate":"1970-01-01T00:00:00Z", "viewPassword":true,
      "login":{
        "username":"enc-user", "password":"enc-password", "passwordRevisionDate":null,
        "autofillOnPageLoad":false, "totp":"enc-totp", "uri":"enc-uri",
        "uris":[{"uri":"enc-uri","match":0,"uriChecksum":"enc-checksum"},{"uri":null}],
        "fido2Credentials":[{
          "credentialId":"enc-id", "keyType":"enc-type", "keyAlgorithm":"enc-algorithm",
          "keyCurve":"enc-curve", "keyValue":"enc-key", "rpId":"enc-rp", "rpName":null,
          "userHandle":null, "userName":null, "userDisplayName":null, "counter":"enc-counter",
          "discoverable":"enc-discoverable", "creationDate":"2024-01-01T00:00:00Z"
        }]
      },
      "card":{"cardholderName":null,"brand":null,"number":null,"expMonth":null,"expYear":null,"code":null},
      "identity":{
        "title":null,"firstName":null,"middleName":null,"lastName":null,"address1":null,"address2":null,
        "address3":null,"city":null,"state":null,"postalCode":null,"country":null,"company":null,
        "email":null,"phone":null,"ssn":null,"username":null,"passportNumber":null,"licenseNumber":null
      },
      "secureNote":{"type":0}, "sshKey":{"privateKey":"enc-private","publicKey":null,"keyFingerprint":null},
      "fields":[{"type":0,"name":"enc-field","value":"enc-value","linkedId":null},{"type":1}],
      "passwordHistory":[{"password":"enc-old","lastUsedDate":"2023-01-01T00:00:00Z"}],
      "permissions":{"delete":true,"restore":false},
      "bankAccount":null, "driversLicense":null, "passport":null,
      "attachments":[{
        "object":"attachment", "id":"attachment-1", "url":null,"fileName":"enc-name",
        "key":"enc-key","size":"128","sizeName":"128 bytes"
      }]
    }
    """

    private func decode(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> CipherResponseDTO {
        var object = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        mutate(&object)
        return try JSONDecoder().decode(CipherResponseDTO.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func addingUnknown(to value: Any, at path: ArraySlice<String>) -> Any {
        guard let component = path.first else {
            var object = value as! [String: Any]
            object["futureEncryptedField"] = ["opaque": "synthetic-future-value"]
            return object
        }
        if let index = Int(component) {
            var array = value as! [Any]
            array[index] = addingUnknown(to: array[index], at: path.dropFirst())
            return array
        }
        var object = value as! [String: Any]
        object[component] = addingUnknown(to: object[component]!, at: path.dropFirst())
        return object
    }

    @Test
    func supportedShapeAndExistingResponseDiscriminatorsRemainEditable() throws {
        let dto = try decode()
        #expect(!dto.hasUnrecognizedPayload)
        #expect(dto.edit == true)
        #expect(try dto.toSDKCipher().edit)
        _ = try CipherRequestDTO(cipher: dto.toSDKCipher(), encryptedFor: "user-1")
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: Any])
        #expect(encoded["_nativeHasUnrecognizedPayload"] == nil)
    }

    @Test
    func emptyNewCipherTypeSlotsDoNotBlockSupportedCipherEdits() throws {
        let dto = try decode()
        #expect(!dto.hasUnrecognizedPayload)
        #expect(dto.edit == true)
        _ = try CipherRequestDTO(cipher: dto.toSDKCipher(), encryptedFor: "user-1")
    }

    @Test
    func matchingVaultwardenLegacyURIAliasDoesNotBlockEditsButConflictingAliasDoes() throws {
        let matching = try decode()
        #expect(!matching.hasUnrecognizedPayload)
        #expect(matching.login?.uris?.first?.uri == "enc-uri")

        let conflicting = try decode {
            var login = $0["login"] as! [String: Any]
            login["uri"] = "different-encrypted-uri"
            $0["login"] = login
        }
        #expect(conflicting.hasUnrecognizedPayload)
        #expect(conflicting.edit == false)
    }

    @Test(arguments: ["bankAccount", "driversLicense", "passport"])
    func nonemptyUnsupportedCipherTypeSlotsRemainReadOnly(_ field: String) throws {
        let dto = try decode { $0[field] = ["name": "synthetic-encrypted-future-type"] }
        #expect(dto.hasUnrecognizedPayload)
        #expect(dto.edit == false)
        #expect(throws: CipherMappingError.unsupportedPayload) {
            _ = try CipherRequestDTO(cipher: dto.toSDKCipher(), encryptedFor: "user-1")
        }
    }

    @Test(arguments: [
        "", "login", "login.uris.1", "login.fido2Credentials.0", "card", "identity", "secureNote", "sshKey",
        "fields.1", "passwordHistory.0", "permissions", "attachments.0",
    ])
    func unknownFieldsAtEveryWritableDepthAreReadOnly(_ path: String) throws {
        let components = path.isEmpty ? [] : path.components(separatedBy: ".")
        let dto = try decode { $0 = addingUnknown(to: $0, at: components[...]) as! [String: Any] }
        #expect(dto.hasUnrecognizedPayload)
        #expect(dto.edit == false)
        let cipher = try dto.toSDKCipher()
        #expect(cipher.name == "enc-name" && cipher.login?.password == "enc-password")
        #expect(!cipher.edit)
        #expect(throws: CipherMappingError.unsupportedPayload) {
            _ = try CipherRequestDTO(cipher: cipher, encryptedFor: "user-1")
        }
    }

    @Test(arguments: ["null", "false", "string", "array", "object"])
    func evenNullOrEmptyUnknownFieldsCannotBeAssumedHarmless(_ kind: String) throws {
        let unknown: Any = switch kind {
        case "null": NSNull()
        case "false": false
        case "string": ""
        case "array": [Any]()
        default: [String: Any]()
        }
        let dto = try decode {
            $0["futureField"] = unknown
            $0["_nativeHasUnrecognizedPayload"] = false
        }
        #expect(dto.hasUnrecognizedPayload)
        #expect(try !dto.toSDKCipher().edit)
    }

    @Test
    func unknownObjectInsideLoginIsNotTreatedAsAResponseDiscriminator() throws {
        let dto = try decode {
            var login = $0["login"] as! [String: Any]
            login["object"] = "future-login-data"
            $0["login"] = login
        }
        #expect(dto.hasUnrecognizedPayload)
    }

    @Test
    func encryptedProjectionRoundTripRetainsSafetyEvenAfterUnknownValuesAreOmitted() throws {
        let dto = try decode { $0["futureField"] = "synthetic-future-value" }
        let encoded = try JSONEncoder().encode(dto)
        let cached = try JSONDecoder().decode(CipherResponseDTO.self, from: encoded)
        #expect(cached.hasUnrecognizedPayload && cached.edit == false)
        #expect(try !cached.toSDKCipher().edit)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["edit"] as? Bool == false) // old readers also see read-only
        #expect(object["_nativeHasUnrecognizedPayload"] as? Bool == true)
        #expect(encoded.range(of: Data("synthetic-future-value".utf8)) == nil)
    }

    @Test
    func changingPublicEditFlagCannotRemoveTheCapturedSafetyFence() throws {
        var dto = try decode { $0["futureField"] = true }
        dto.edit = true
        #expect(try !dto.toSDKCipher().edit)
        #expect(throws: CipherMappingError.unsupportedPayload) {
            _ = try CipherRequestDTO(cipher: dto.toSDKCipher(), encryptedFor: "user-1")
        }
        let cached = try JSONDecoder().decode(CipherResponseDTO.self, from: JSONEncoder().encode(dto))
        #expect(cached.hasUnrecognizedPayload && cached.edit == false)
        struct OlderReader: Decodable { let edit: Bool }
        #expect(try !JSONDecoder().decode(OlderReader.self, from: JSONEncoder().encode(dto)).edit)
    }

    @Test
    func retainedDecryptedPasskeyTargetCannotBypassUnsupportedPayloadFence() {
        let target = SDKAutoFillCredentialView(legacyView: .fixture(), supportsLosslessEditing: false)
        #expect(target.login?.password != nil)
        #expect(!target.edit && !target.allowsPasskeyRegistration)
    }
}
