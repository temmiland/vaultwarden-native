import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Networking
import Testing

@Suite
struct SDKVaultSyncTests {
    private var environment: Domain.ServerEnvironment {
        get throws { try Domain.ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!) }
    }

    private let syncJSON = """
    {
        "folders": [
            { "id": "folder-1", "name": "Work", "revisionDate": "2024-01-01T00:00:00.000Z" }
        ],
        "ciphers": [
            {
                "id": "cipher-1",
                "type": 1,
                "name": "Encrypted Name",
                "favorite": false,
                "reprompt": 0,
                "revisionDate": "2024-01-01T00:00:00.000Z",
                "creationDate": "2024-01-01T00:00:00.000Z",
                "login": { "username": "enc-username", "password": "enc-password" }
            }
        ]
    }
    """

    @Test
    func syncParsesResponseAndDecryptsThroughCryptoService() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responses = [HTTPResponse(statusCode: 200, headers: [:], body: Data(syncJSON.utf8))]

        let cryptoService = SpyVaultCryptoService()
        cryptoService.decryptCiphersResult = [.fixture(id: "cipher-1", name: "Decrypted Name")]
        cryptoService.decryptFoldersResult = [FolderView(id: "folder-1", name: "Work", revisionDate: Date())]

        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: cryptoService,
            accessToken: { "access-token" }, checkAccess: { try Task.checkCancellation() }
        )

        let result = try await service.fetchOutput()

        // The service must decrypt everything through the crypto service, not hand raw/encrypted
        // data back to the caller.
        #expect(result.snapshot.items.map(\.name) == ["Decrypted Name"])
        #expect(result.snapshot.folders.map(\.name) == ["Work"])
        #expect(result.snapshot.collections.isEmpty)
        #expect(Array(cryptoService.events.prefix(4)) == [
            "initializeOrganizationCrypto(0)", "decryptCiphers(1)", "decryptFolders(1)", "decryptCollections(0)",
        ])

        // Confirms the request carried the bearer token and hit the right endpoint.
        let request = try #require(httpClient.calls.first?.request)
        #expect(request.url.path.hasSuffix("/api/sync"))
        #expect(request.headers["Authorization"] == "Bearer access-token")
    }

    @Test
    func syncPropagatesTheParsedCipherIntoTheCryptoServiceCall() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responses = [HTTPResponse(statusCode: 200, headers: [:], body: Data(syncJSON.utf8))]
        let cryptoService = SpyVaultCryptoService()

        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: cryptoService,
            accessToken: { "token" }, checkAccess: { try Task.checkCancellation() }
        )

        _ = try await service.fetchOutput()

        #expect(cryptoService.events.contains("decryptCiphers(1)"))
    }

    /// Regression test for the actual bug reported during manual testing: org-owned ciphers
    /// failed to decrypt (per-field, silently - the Rust core only logs "Missing Key for Id:
    /// Organization(...)") because the org's key from `profile.organizations[]` was never
    /// registered with the SDK before decrypting.
    @Test
    func syncRegistersOrganizationKeysFromProfileBeforeDecryptingCiphers() async throws {
        let json = """
        {
            "profile": {
                "organizations": [
                    { "id": "org-1", "name": "Acme Inc", "key": "wrapped-org-key" }
                ]
            },
            "collections": [
                { "id": "col-1", "organizationId": "org-1", "name": "enc-collection-name", "readOnly": false, "manage": true }
            ],
            "ciphers": [
                {
                    "id": "cipher-1",
                    "organizationId": "org-1",
                    "type": 1,
                    "name": "Encrypted Name",
                    "favorite": false,
                    "reprompt": 0,
                    "revisionDate": "2024-01-01T00:00:00.000Z",
                    "creationDate": "2024-01-01T00:00:00.000Z",
                    "login": { "username": "enc-username", "password": "enc-password" }
                }
            ]
        }
        """
        let httpClient = MockHTTPClient()
        httpClient.responses = [HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8))]
        let cryptoService = SpyVaultCryptoService()
        cryptoService.decryptCiphersResult = [.fixture(id: "cipher-1", name: "Decrypted Name")]

        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: cryptoService,
            accessToken: { "token" }, checkAccess: { try Task.checkCancellation() }
        )

        let result = try await service.fetchOutput()

        #expect(cryptoService.lastOrganizationKeys == ["org-1": "wrapped-org-key"])
        #expect(result.snapshot.organizationNames == [OrganizationID(rawValue: "org-1"): "Acme Inc"])
        // Org keys must be registered before any cipher/collection decrypt call.
        let orgIndex = try #require(cryptoService.events.firstIndex(of: "initializeOrganizationCrypto(1)"))
        let cipherIndex = try #require(cryptoService.events.firstIndex(of: "decryptCiphers(1)"))
        let collectionIndex = try #require(cryptoService.events.firstIndex(of: "decryptCollections(1)"))
        #expect(orgIndex < cipherIndex)
        #expect(orgIndex < collectionIndex)
    }

    @Test
    func syncThrowsWhenAccessTokenIsMissing() async throws {
        let httpClient = MockHTTPClient()
        let cryptoService = SpyVaultCryptoService()
        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: cryptoService,
            accessToken: { nil }, checkAccess: { try Task.checkCancellation() }
        )

        await #expect(throws: VaultRepositoryError.sessionClosed) {
            _ = try await service.fetchOutput()
        }
        #expect(httpClient.calls.isEmpty)
    }

    @Test
    func syncThrowsHTTPStatusErrorOnFailureStatusCode() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responses = [HTTPResponse(statusCode: 401, headers: [:], body: Data())]
        let cryptoService = SpyVaultCryptoService()
        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: cryptoService,
            accessToken: { "token" }, checkAccess: { try Task.checkCancellation() }
        )

        await #expect(throws: HTTPStatusError.self) {
            _ = try await service.fetchOutput()
        }
        #expect(cryptoService.events.isEmpty)
    }

    @Test
    func malformedCipherDoesNotHideReadableItemsOrPretendTheVaultIsComplete() async throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(syncJSON.utf8)) as? [String: Any])
        var ciphers = try #require(json["ciphers"] as? [[String: Any]])
        var malformed = try #require(ciphers.first)
        malformed["id"] = "unavailable-id"
        malformed["type"] = 256
        ciphers.append(malformed)
        json["ciphers"] = ciphers

        let httpClient = MockHTTPClient()
        httpClient.responses = [
            .init(statusCode: 200, headers: [:], body: try JSONSerialization.data(withJSONObject: json)),
        ]
        let crypto = SpyVaultCryptoService()
        crypto.decryptCiphersResult = [.fixture(id: "cipher-1", name: "Readable")]
        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: crypto,
            accessToken: { "token" },
            checkAccess: { try Task.checkCancellation() }
        )

        let result = try await service.fetchOutput()

        #expect(result.snapshot.items.map(\.id.rawValue) == ["cipher-1"])
        #expect(crypto.lastDecryptedCiphers.map(\.id) == ["cipher-1"])
        #expect(result.snapshot.warnings == [.unavailableItems(count: 1)])
    }

    @Test
    func omittedDecryptionResultsAreReportedAsUnavailable() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responses = [.init(statusCode: 200, headers: [:], body: Data(syncJSON.utf8))]
        let crypto = SpyVaultCryptoService()
        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: crypto,
            accessToken: { "token" },
            checkAccess: { try Task.checkCancellation() }
        )

        let result = try await service.fetchOutput()

        #expect(result.snapshot.items.isEmpty)
        #expect(result.snapshot.warnings == [.unavailableItems(count: 1)])
    }

    @Test
    func deletedUnsupportedItemsDoNotProduceAnActiveVaultWarning() async throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(syncJSON.utf8)) as? [String: Any])
        var ciphers = try #require(json["ciphers"] as? [[String: Any]])
        ciphers[0]["deletedDate"] = "2024-01-01T00:00:00Z"
        ciphers[0]["type"] = 256
        json["ciphers"] = ciphers
        let httpClient = MockHTTPClient()
        httpClient.responses = [
            .init(statusCode: 200, headers: [:], body: try JSONSerialization.data(withJSONObject: json)),
        ]
        let crypto = SpyVaultCryptoService()
        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: crypto,
            accessToken: { "token" },
            checkAccess: { try Task.checkCancellation() }
        )

        let result = try await service.fetchOutput()

        #expect(crypto.lastDecryptedCiphers.isEmpty)
        #expect(result.snapshot.warnings.isEmpty)
    }

    @Test
    func duplicateOrganizationIDsFailSafelyRatherThanTrappingInADictionaryInitializer() async throws {
        let json = """
        { "profile": { "organizations": [
            { "id": "same-id", "key": "enc-key-1" },
            { "id": "same-id", "key": "enc-key-2" }
        ] }, "ciphers": [] }
        """
        let httpClient = MockHTTPClient()
        httpClient.responses = [.init(statusCode: 200, headers: [:], body: Data(json.utf8))]
        let crypto = SpyVaultCryptoService()
        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: crypto,
            accessToken: { "token" },
            checkAccess: { try Task.checkCancellation() }
        )

        await #expect(throws: CipherMappingError.invalidField("profile.organizations.id")) {
            _ = try await service.fetchOutput()
        }
        #expect(crypto.events.isEmpty)
    }

    @Test
    func duplicateCipherIDsDoNotExposeAnAmbiguousEditableCopy() async throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(syncJSON.utf8)) as? [String: Any])
        let original = try #require((json["ciphers"] as? [[String: Any]])?.first)
        json["ciphers"] = [original, original]
        let httpClient = MockHTTPClient()
        httpClient.responses = [
            .init(statusCode: 200, headers: [:], body: try JSONSerialization.data(withJSONObject: json)),
        ]
        let crypto = SpyVaultCryptoService()
        let service = SDKVaultSessionSource(
            http: httpClient,
            environment: try environment,
            crypto: crypto,
            accessToken: { "token" },
            checkAccess: { try Task.checkCancellation() }
        )

        let result = try await service.fetchOutput()

        #expect(crypto.lastDecryptedCiphers.isEmpty)
        #expect(result.snapshot.items.isEmpty)
        #expect(result.snapshot.warnings == [.unavailableItems(count: 2)])
    }
}
