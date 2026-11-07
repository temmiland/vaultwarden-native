import AutoFillContract
import AutoFillData
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct LegacyAutoFillCacheStoreTests {
    @Test
    func confirmedMutationAdvancesBothFencesAndKeepsOtherEncryptedRecords() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = LegacyAutoFillCacheStore(
            directoryURL: fixture.directory,
            authorization: AuthorizationFixture(currentProof: fixture.proof)
        )

        try store.upsert(
            try cipher(id: "cipher-2"),
            for: fixture.proof.account,
            requiringProof: fixture.proof,
            cacheRevision: fixture.cacheRevision
        )

        let cache = try #require(try store.read())
        #expect(cache.ciphers.map(\.id) == ["cipher-1", "cipher-2"])
        #expect(cache.organizationKeys == ["org-1": "encrypted-org-key"])
        #expect(cache.owner == fixture.proof.account)
        #expect(cache.revision != fixture.cacheRevision)
        #expect(cache.projectionRevision == 18)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.cacheURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test
    func cacheReadStopsAtTheConfiguredByteLimit() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = LegacyAutoFillCacheStore(
            directoryURL: fixture.directory,
            authorization: AuthorizationFixture(currentProof: fixture.proof),
            maximumCacheBytes: 8
        )
        #expect(throws: SharedVaultCacheError.cacheTooLarge) { _ = try store.read() }
    }

    @Test(
        arguments: [
            "stale-unlock",
            "stale-cache",
            "wrong-account",
            "exhausted-revision",
            "missing-cache",
            "authorization-error",
        ]
    )
    func rejectedMutationCannotChangeOrInventACache(_ reason: String) throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var currentProof = fixture.proof
        var expectedRevision = fixture.cacheRevision
        var owner = fixture.proof.account
        switch reason {
        case "stale-unlock": currentProof = ExtensionUnlockProof(account: fixture.proof.account)
        case "stale-cache": expectedRevision = UUID()
        case "wrong-account": owner = AutoFillAccountIdentity(
                userID: owner.userID,
                serverBaseURL: URL(string: "https://another-vault.example.com")!
            )
        case "exhausted-revision":
            var cache = try JSONDecoder().decode(
                SharedVaultCacheData.self,
                from: Foundation.Data(contentsOf: fixture.cacheURL)
            )
            cache.projectionRevision = .max
            try JSONEncoder().encode(cache).write(to: fixture.cacheURL)
        case "missing-cache": try FileManager.default.removeItem(at: fixture.cacheURL)
        default: break
        }
        let original = try? Foundation.Data(contentsOf: fixture.cacheURL)
        let store = LegacyAutoFillCacheStore(
            directoryURL: fixture.directory,
            authorization: AuthorizationFixture(currentProof: currentProof, failRead: reason == "authorization-error")
        )

        #expect(throws: (any Error).self) {
            try store.upsert(
                cipher(id: "cipher-2"),
                for: owner,
                requiringProof: fixture.proof,
                cacheRevision: expectedRevision
            )
        }
        #expect((try? Foundation.Data(contentsOf: fixture.cacheURL)) == original)
    }

    private struct Fixture {
        let directory: URL
        let cacheURL: URL
        let proof: ExtensionUnlockProof
        let cacheRevision: UUID

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "autofill-cache-test-\(UUID().uuidString)"
            )
            cacheURL = directory.appendingPathComponent("autofill-cache.json")
            proof = ExtensionUnlockProof(account: AutoFillAccountIdentity(
                userID: "account-1",
                serverBaseURL: URL(string: "https://vault.example.com")!
            ))
            cacheRevision = UUID()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            let cache = SharedVaultCacheData(
                ciphers: [try LegacyAutoFillCacheStoreTests.cipher(id: "cipher-1")],
                organizationKeys: ["org-1": "encrypted-org-key"],
                updatedAt: .distantPast,
                owner: proof.account,
                revision: cacheRevision,
                projectionRevision: 17
            )
            try JSONEncoder().encode(cache).write(to: cacheURL)
        }
    }

    private struct AuthorizationFixture: AutoFillCacheMutationAuthorizing {
        let currentProof: ExtensionUnlockProof
        var failRead = false

        func withAuthorizedCacheMutation<Value>(
            requiring proof: ExtensionUnlockProof,
            _ operation: () throws -> Value
        ) throws -> Value {
            if failRead { throw CocoaError(.fileReadNoPermission) }
            guard currentProof == proof else { throw CancellationError() }
            return try operation()
        }
    }

    private static func cipher(id: String) throws -> CipherResponseDTO {
        try JSONDecoder().decode(CipherResponseDTO.self, from: Foundation.Data(
            """
            {"id":"\(id)","type":1,"name":"encrypted-name","reprompt":0,
             "login":{"username":"encrypted-user","password":"encrypted-password"}}
            """.utf8
        ))
    }

    private func cipher(id: String) throws -> CipherResponseDTO { try Self.cipher(id: id) }
}
