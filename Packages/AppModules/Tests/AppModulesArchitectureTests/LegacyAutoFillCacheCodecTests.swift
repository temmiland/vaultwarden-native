import AutoFillContract
import AutoFillData
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct LegacyAutoFillCacheCodecTests {
    @Test
    func roundTripsEncryptedPayloadsAndProjectionRevisionThroughExistingCacheFormat() throws {
        let owner = AutoFillAccountIdentity(
            userID: "account-1", serverBaseURL: URL(string: "https://vault.example.com")!
        )
        let cipher = CipherResponseDTO(
            id: "cipher-1", organizationId: nil, folderId: nil, collectionIds: nil, type: 1,
            name: "encrypted-name", notes: nil, favorite: false, reprompt: 0, key: "encrypted-key",
            login: nil, card: nil, identity: nil, secureNote: nil, sshKey: nil, organizationUseTotp: nil,
            edit: nil, viewPassword: nil, attachments: nil, revisionDate: nil, creationDate: nil,
            deletedDate: nil, archivedDate: nil
        )
        let payload = try JSONEncoder().encode(cipher)
        let envelope = try AutoFillCacheEnvelope(
            accountID: owner.userID, revision: 17, generatedAt: Date(timeIntervalSince1970: 1_000),
            encryptedLoginRecords: [
                EncryptedLoginRecord(id: "cipher-1", deletedAt: nil, encryptedCipherPayload: payload),
            ],
            encryptedOrganizationKeys: ["org-1": "encrypted-org-key"]
        )
        let codec = LegacyAutoFillCacheCodec(owner: owner)

        let legacyData = try codec.encode(envelope)
        let decoded = try codec.decode(legacyData)

        #expect(decoded.revision == 17)
        #expect(decoded.encryptedOrganizationKeys == ["org-1": "encrypted-org-key"])
        #expect(decoded.encryptedLoginRecords.first?.id == "cipher-1")
        let decodedPayload = try #require(decoded.encryptedLoginRecords.first?.encryptedCipherPayload)
        // The legacy bridge decodes/re-encodes JSON, not an opaque byte stream. Compare the full
        // payload while ignoring object-key order, which JSONEncoder does not guarantee.
        let expectedObject = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let decodedObject = try #require(JSONSerialization.jsonObject(with: decodedPayload) as? [String: Any])
        #expect(NSDictionary(dictionary: decodedObject) == NSDictionary(dictionary: expectedObject))
    }

    @Test
    func reorderedJSONObjectsKeepAllEncryptedValues() throws {
        let owner = AutoFillAccountIdentity(
            userID: "account-1",
            serverBaseURL: URL(string: "https://vault.example.com")!
        )
        let codec = LegacyAutoFillCacheCodec(owner: owner)
        let payloads = [
            #"{"id":"cipher-1","type":1,"name":"encrypted-name","favorite":false,"reprompt":0,"key":"encrypted-key"}"#,
            #"{"key":"encrypted-key","reprompt":0,"favorite":false,"name":"encrypted-name","type":1,"id":"cipher-1"}"#,
        ]
        var objects: [NSDictionary] = []
        for value in payloads {
            let envelope = try AutoFillCacheEnvelope(
                accountID: owner.userID,
                revision: 17,
                generatedAt: .distantPast,
                encryptedLoginRecords: [EncryptedLoginRecord(
                    id: "cipher-1",
                    deletedAt: nil,
                    encryptedCipherPayload: Data(value.utf8)
                )],
                encryptedOrganizationKeys: [:]
            )
            let roundTrip = try codec.decode(codec.encode(envelope))
            let payload = try #require(roundTrip.encryptedLoginRecords.first?.encryptedCipherPayload)
            objects.append(
                NSDictionary(dictionary: try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any]))
            )
        }
        #expect(objects.count == 2 && objects[0] == objects[1])
        #expect(objects[0]["key"] as? String == "encrypted-key")
        #expect(objects[0]["name"] as? String == "encrypted-name")
    }

    @Test
    func refusesToEncodeAnEnvelopeForAnotherAccount() throws {
        let owner = AutoFillAccountIdentity(
            userID: "account-1", serverBaseURL: URL(string: "https://vault.example.com")!
        )
        let envelope = try AutoFillCacheEnvelope(
            accountID: "account-2", revision: 1, generatedAt: .distantPast,
            encryptedLoginRecords: [], encryptedOrganizationKeys: [:]
        )

        #expect(throws: SharedVaultCacheError.self) {
            try LegacyAutoFillCacheCodec(owner: owner).encode(envelope)
        }
    }
}
