@testable import BitwardenSDKAdapter
import Foundation
import Testing

/// Exercises the real wire -> SDK value -> wire boundary, without a logged-in FFI client.
/// All strings below are fabricated encrypted-payload placeholders, not credentials.
@Suite
struct CipherWireContractTests {
    private let fixture = """
    {
        "id": "cipher-1", "type": 1, "name": "enc-name", "notes": "enc-notes",
        "favorite": true, "reprompt": 1, "key": "enc-cipher-key",
        "revisionDate": "2024-01-01T00:00:00.123Z", "creationDate": "2023-01-01T00:00:00Z",
        "permissions": { "delete": false, "restore": true },
        "fields": [
            { "type": 0, "name": "enc-text-name", "value": "enc-text-value" },
            { "type": 1, "name": "enc-hidden-name", "value": "enc-hidden-value" },
            { "type": 2, "name": "enc-boolean-name", "value": "enc-boolean-value" },
            { "type": 3, "name": "enc-linked-name", "linkedId": 100 }
        ],
        "passwordHistory": [
            { "password": "enc-old-password", "lastUsedDate": "2023-06-01T01:02:03.456Z" }
        ],
        "attachments": [
            { "id": "attachment-1", "fileName": "enc-filename", "key": "enc-attachment-key", "size": "128" }
        ],
        "login": {
            "username": "enc-username", "password": "enc-password", "totp": "enc-totp",
            "autofillOnPageLoad": false,
            "uris": [ { "uri": "enc-uri", "match": 3, "uriChecksum": "enc-checksum" } ]
        }
    }
    """

    private func response(mutating update: (inout [String: Any]) -> Void = { _ in }) throws -> CipherResponseDTO {
        var object = try #require(JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any])
        update(&object)
        return try JSONDecoder().decode(CipherResponseDTO.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test
    func wireRoundTripPreservesUneditedEncryptedDataAndMetadata() throws {
        let original = try response()
        let cipher = try original.toSDKCipher()
        let request = try CipherRequestDTO(cipher: cipher, encryptedFor: "user-1")
        let decoded = try JSONDecoder().decode(CipherRequestDTO.self, from: JSONEncoder().encode(request))

        #expect(cipher.fields?.count == 4)
        #expect(cipher.permissions?.delete == false)
        #expect(cipher.permissions?.restore == true)
        #expect(decoded.fields?.map(\.type) == [0, 1, 2, 3])
        #expect(decoded.fields?.map(\.name) == original.fields?.map(\.name))
        #expect(decoded.fields?.map(\.value) == original.fields?.map(\.value))
        #expect(decoded.fields?.last?.linkedId == 100)
        #expect(decoded.passwordHistory?.first?.password == "enc-old-password")
        #expect(decoded.passwordHistory?.first?.lastUsedDate == "2023-06-01T01:02:03.456Z")
        #expect(decoded.attachments2?["attachment-1"]?.fileName == "enc-filename")
        #expect(decoded.attachments2?["attachment-1"]?.key == "enc-attachment-key")
        #expect(decoded.login?.uris?.first?.uriChecksum == "enc-checksum")
        #expect(decoded.login?.uris?.first?.match == 3)
        #expect(decoded.login?.autofillOnPageLoad == false)
        #expect(decoded.key == "enc-cipher-key")
        #expect(decoded.encryptedFor == "user-1")
    }

    @Test
    func cipherWritesRequireTheEncryptingUserIdentity() throws {
        let cipher = try response().toSDKCipher()
        #expect(throws: CipherMappingError.missingRequiredField("encryptedFor")) {
            _ = try CipherRequestDTO(cipher: cipher, encryptedFor: "")
        }
    }

    @Test
    func cipherUpdatesCarryTheBaseRevisionForServerConflictDetectionButCreatesOmitIt() throws {
        let cipher = try response().toSDKCipher()
        let update = try CipherRequestDTO(
            cipher: cipher, encryptedFor: "user-1", lastKnownRevisionDate: cipher.revisionDate
        )
        let updateObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any]
        )
        let lastKnown = try #require(updateObject["lastKnownRevisionDate"] as? String)
        #expect(ServerDateParsing.parse(lastKnown) == cipher.revisionDate)

        let create = try CipherRequestDTO(cipher: cipher, encryptedFor: "user-1")
        let createObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(create)) as? [String: Any]
        )
        #expect(create.lastKnownRevisionDate == nil)
        #expect(createObject["lastKnownRevisionDate"] == nil)
    }

    @Test
    func encryptedForResponseMetadataIsRecognizedAndRetained() throws {
        let original = try response { $0["encryptedFor"] = "user-1" }
        #expect(!original.hasUnrecognizedPayload)
        #expect(original.encryptedFor == "user-1")

        let cached = try JSONDecoder().decode(CipherResponseDTO.self, from: JSONEncoder().encode(original))
        #expect(cached.encryptedFor == "user-1")
        #expect(!cached.hasUnrecognizedPayload)
        #expect(try cached.toSDKCipher().name == "enc-name")
    }

    @Test
    func olderPayloadsWithoutOptionalMetadataStillDecodeAndEncode() throws {
        let original = try response { object in
            for key in ["fields", "passwordHistory", "permissions", "attachments"] {
                object.removeValue(forKey: key)
            }
        }
        let request = try CipherRequestDTO(cipher: original.toSDKCipher(), encryptedFor: "user-1")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])

        #expect(request.fields == nil)
        #expect(request.passwordHistory == nil)
        #expect(request.attachments2 == nil)
        #expect(object["fields"] == nil)
        #expect(object["passwordHistory"] == nil)
        #expect(object["attachments2"] == nil)
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func existingEditableCipherTypesRetainTheirPayloadAndHiddenMetadata(_ type: Int) throws {
        let payloads: [Int: (key: String, value: [String: Any])] = [
            1: ("login", ["username": "enc-user", "password": "enc-password"]),
            2: ("secureNote", ["type": 0]),
            3: ("card", ["cardholderName": "enc-holder", "number": "enc-number", "code": "enc-code"]),
            4: (
                "identity",
                ["firstName": "enc-first", "address1": "enc-address", "company": "enc-company", "ssn": "enc-ssn"]
            ),
            5: ("sshKey", ["privateKey": "enc-private", "publicKey": "enc-public", "keyFingerprint": "enc-fingerprint"]),
        ]
        let payload = try #require(payloads[type])
        let original = try response {
            $0.removeValue(forKey: "login")
            $0["type"] = type
            $0[payload.key] = payload.value
        }
        let request = try CipherRequestDTO(cipher: original.toSDKCipher(), encryptedFor: "user-1")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let sentPayload = try #require(object[payload.key] as? [String: Any])

        #expect(NSDictionary(dictionary: sentPayload) == NSDictionary(dictionary: payload.value))
        #expect(request.fields?.count == 4)
        #expect(request.passwordHistory?.first?.password == "enc-old-password")
        #expect(request.attachments2?["attachment-1"]?.key == "enc-attachment-key")
    }

    @Test(arguments: [-1, 256, Int.max])
    func outOfRangeCipherTypesThrowRatherThanTrap(_ value: Int) throws {
        let original = try response { $0["type"] = value }
        #expect(throws: CipherMappingError.invalidField("type")) { _ = try original.toSDKCipher() }
    }

    @Test
    func malformedEnumsAreNotCoercedIntoEditableDefaults() throws {
        let cases: [(String, Any, String)] = [
            ("fields", [["type": -1]], "fields.type"),
            ("fields", [["type": 3, "linkedId": -1]], "fields.linkedId"),
            ("login", ["uris": [["match": 256]]], "login.uris.match"),
            ("secureNote", ["type": -1], "secureNote.type"),
            ("reprompt", 256, "reprompt"),
        ]
        for (key, value, field) in cases {
            let original = try response { $0[key] = value }
            #expect(throws: CipherMappingError.invalidField(field)) { _ = try original.toSDKCipher() }
        }
    }

    @Test
    func invalidDatesCannotClearDeletionArchiveOrHistoryMetadata() throws {
        for key in ["deletedDate", "archivedDate", "creationDate", "revisionDate"] {
            let original = try response { $0[key] = "invalidZ." }
            #expect(throws: CipherMappingError.invalidField(key)) { _ = try original.toSDKCipher() }
        }
        let history = try response {
            $0["passwordHistory"] = [["password": "enc-old-password", "lastUsedDate": "invalidZ."]]
        }
        #expect(throws: CipherMappingError.invalidField("passwordHistory.lastUsedDate")) {
            _ = try history.toSDKCipher()
        }
        #expect(ServerDateParsing.parse("2024-01-01T00:00:00.123garbageZ") == nil)
        #expect(ServerDateParsing.parse("2024-01-01T00:00:00Z.") == nil)
        #expect(ServerDateParsing.parse("2024-01-01T00:00:00.1234567Z") != nil)
    }

    @Test
    func unsupportedBlobPayloadCannotBeReconstructedAsAnEmptyEditableItem() throws {
        let original = try response { $0["data"] = "opaque-unsupported-payload" }
        #expect(throws: CipherMappingError.unsupportedPayload) { _ = try original.toSDKCipher() }
        let encoded = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(CipherResponseDTO.self, from: encoded).data == "opaque-unsupported-payload")
    }

    @Test
    func incompleteRequiredPayloadsCannotBeSilentlyRebuilt() throws {
        let missingName = try response { $0.removeValue(forKey: "name") }
        #expect(throws: CipherMappingError.missingRequiredField("name")) { _ = try missingName.toSDKCipher() }
        let missingSSHKey = try response {
            $0["type"] = 5
            $0["sshKey"] = ["publicKey": "enc-public", "keyFingerprint": "enc-fingerprint"]
        }
        #expect(throws: CipherMappingError.missingRequiredField("sshKey.privateKey")) { _ = try missingSSHKey.toSDKCipher(
        ) }
    }

    @Test
    func duplicateOrMissingAttachmentIDsCannotBeSilentlyDroppedFromAnUpdate() throws {
        let duplicate = try response {
            $0["attachments"] = [
                ["id": "same-id", "fileName": "enc-name-1", "key": "enc-key-1"],
                ["id": "same-id", "fileName": "enc-name-2", "key": "enc-key-2"],
            ]
        }
        let duplicateCipher = try duplicate.toSDKCipher()
        #expect(throws: CipherMappingError.invalidField("attachments.id")) {
            _ = try CipherRequestDTO(cipher: duplicateCipher, encryptedFor: "user-1")
        }
        let missing = try response { $0["attachments"] = [["key": "enc-key"]] }
        let missingCipher = try missing.toSDKCipher()
        #expect(throws: CipherMappingError.missingRequiredField("attachments.id")) {
            _ = try CipherRequestDTO(cipher: missingCipher, encryptedFor: "user-1")
        }
        let missingName = try response { $0["attachments"] = [["id": "attachment-1", "key": "enc-key"]] }
        let missingNameCipher = try missingName.toSDKCipher()
        #expect(throws: CipherMappingError.missingRequiredField("attachments.fileName")) {
            _ = try CipherRequestDTO(cipher: missingNameCipher, encryptedFor: "user-1")
        }
    }
}
