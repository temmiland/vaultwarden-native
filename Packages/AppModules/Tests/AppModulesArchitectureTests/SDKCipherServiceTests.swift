import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Networking
import Testing

@Suite
struct SDKCipherServiceTests {
    private let apiURL = URL(string: "https://vault.example.com/api")!

    @Test
    func passwordUpdateUsesTheObservedServerRevisionRatherThanTheNewEncryptionTimestamp() async throws {
        let http = MockHTTPClient()
        http.responses = [
            HTTPResponse(
                statusCode: 200,
                headers: [:],
                body: try JSONEncoder().encode(AutoFillQuerySourceFixture.dto("existing"))
            ),
        ]
        let service = SDKCipherService(httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { "token" })
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let encrypted = SDKAutoFillEncryptedCipher(
            legacyCipher: .fixture(id: "existing"),
            encryptedFor: "user-1",
            lastKnownRevisionDate: original
        )
        _ = try await service.saveCredentialResponse(encrypted)
        let request = try #require(http.calls.first?.request)
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let revision = try #require(object["lastKnownRevisionDate"] as? String)
        #expect(revision.hasPrefix("2023-11-14T22:13:20"))
        #expect(request.method == .put && request.redirectPolicy == .reject)
    }

    @Test
    func ownedAuthorizationFailureRetainsItsPreSubmissionClassification() async throws {
        let http = MockHTTPClient()
        let service = SDKCipherService(
            httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { "must-not-use-fallback" },
            requireAccessToken: { throw SessionAuthorizationError.refreshRecoveryRequired }
        )
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await service.create(
            .fixture()
        ) }
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await service.savePasskeyResponse(
            .fixture()
        ) }
        #expect(http.calls.isEmpty)
    }

    private func responseJSON(id: String) -> Data {
        Data("""
        {
            "id": "\(id)",
            "type": 1,
            "name": "enc-name",
            "favorite": false,
            "reprompt": 0,
            "revisionDate": "2024-01-01T00:00:00.000Z",
            "creationDate": "2024-01-01T00:00:00.000Z"
        }
        """.utf8)
    }

    @Test
    func unsupportedPayloadCannotReachCreateUpdateOrPasskeyHTTP() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: responseJSON(id: "cipher-1")) as? [String: Any])
        object["futureField"] = "encrypted-future"
        let dto = try JSONDecoder().decode(CipherResponseDTO.self, from: JSONSerialization.data(withJSONObject: object))
        let cipher = try dto.toSDKCipher()
        let http = MockHTTPClient()
        let service = SDKCipherService(httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { "token" })
        await #expect(throws: CipherMappingError.unsupportedPayload) { _ = try await service.create(cipher) }
        await #expect(throws: CipherMappingError.unsupportedPayload) { _ = try await service.update(
            id: "cipher-1",
            cipher
        ) }
        await #expect(throws: SDKPasskeyWriteError.notSubmitted) { _ = try await service.savePasskeyResponse(cipher) }
        #expect(http.calls.isEmpty)
    }

    @Test
    func createPostsToCiphersEndpointWithEncodedCipherBody() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responses = [HTTPResponse(statusCode: 200, headers: [:], body: responseJSON(id: "new-id"))]
        let service = SDKCipherService(
            httpClient: httpClient,
            apiURL: apiURL,
            userID: "user-1",
            accessToken: { "token" }
        )

        let cipher = Cipher.fixture(id: nil, name: "enc-name")
        let created = try await service.create(cipher)

        #expect(created.id == "new-id")
        let request = try #require(httpClient.calls.first?.request)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/api/ciphers"))
        #expect(request.headers["Authorization"] == "Bearer token")

        let body = try #require(request.body)
        let decoded = try JSONDecoder().decode(CipherRequestDTO.self, from: body)
        #expect(decoded.name == "enc-name")
        #expect(decoded.type == 1)
        #expect(decoded.encryptedFor == "user-1")
    }

    @Test
    func updatePutsToCiphersIdEndpoint() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responses = [HTTPResponse(statusCode: 200, headers: [:], body: responseJSON(id: "cipher-1"))]
        let service = SDKCipherService(
            httpClient: httpClient,
            apiURL: apiURL,
            userID: "user-1",
            accessToken: { "token" }
        )

        _ = try await service.update(id: "cipher-1", .fixture(id: "cipher-1"))

        let request = try #require(httpClient.calls.first?.request)
        #expect(request.method == .put)
        #expect(request.url.path.hasSuffix("/api/ciphers/cipher-1"))
    }

    @Test
    func deleteSendsDeleteToCiphersIdEndpoint() async throws {
        let httpClient = MockHTTPClient()
        httpClient.responses = [HTTPResponse(statusCode: 204, headers: [:], body: Data())]
        let service = SDKCipherService(
            httpClient: httpClient,
            apiURL: apiURL,
            userID: "user-1",
            accessToken: { "token" }
        )

        try await service.delete(id: "cipher-1")

        let request = try #require(httpClient.calls.first?.request)
        #expect(request.method == .delete)
        #expect(request.url.path.hasSuffix("/api/ciphers/cipher-1"))
        #expect(request.body == nil)
    }

    @Test
    func requestFailsWhenAccessTokenIsMissing() async throws {
        let httpClient = MockHTTPClient()
        let service = SDKCipherService(httpClient: httpClient, apiURL: apiURL, userID: "user-1", accessToken: { nil })

        await #expect(throws: SDKCipherServiceError.missingAccessToken) {
            _ = try await service.create(.fixture())
        }
        #expect(httpClient.calls.isEmpty)
    }

    @Test
    func passkeyWriteSeparatesDefinitePreSubmitFailureFromTransportUncertainty() async throws {
        let http = MockHTTPClient()
        let missing = SDKCipherService(httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { nil })
        await #expect(throws: SDKPasskeyWriteError.notSubmitted) { _ = try await missing.savePasskeyResponse(.fixture()) }
        #expect(http.calls.isEmpty)
        http.errorToThrow = PasskeyRecoveryFixtureError.write
        let service = SDKCipherService(httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { "token" })
        await #expect(throws: SDKPasskeyWriteError.outcomeUnknown) { _ = try await service.savePasskeyResponse(
            .fixture()
        ) }
        #expect(http.calls.count == 1)
    }

    @Test(arguments: [400, 401, 403, 404, 405, 408, 409, 413, 422, 429, 500, 503])
    func passkeyStatusClassificationDoesNotTreatTimeoutConflictOr5xxAsASafeRetry(_ status: Int) async throws {
        let http = MockHTTPClient()
        http.responses = [HTTPResponse(statusCode: status, headers: [:], body: Data("synthetic server diagnostic".utf8))]
        let service = SDKCipherService(httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { "token" })
        let expected: SDKPasskeyWriteError = [408, 409, 500, 503].contains(status) ? .outcomeUnknown : .rejected
        await #expect(throws: expected) { _ = try await service.savePasskeyResponse(.fixture()) }
    }

    @Test(arguments: ["decode", "missing-create-id", "foreign-update-id", "foreign-encrypted-for", "ineligible"])
    func successfulStatusWithUnusablePasskeyResponseIsConfirmedNotRetryable(_ failure: String) async throws {
        let http = MockHTTPClient()
        var json: [String: Any] = ["type": 1, "name": "encrypted-name", "login": ["username": "encrypted-user"]]
        if failure == "foreign-update-id" { json["id"] = "foreign" }
        if failure == "foreign-encrypted-for" { json["id"] = "saved"; json["encryptedFor"] = "other-user" }
        if failure == "ineligible" { json["id"] = "saved"; json["reprompt"] = 1 }
        let body = failure == "decode" ? Data("broken".utf8) : try JSONSerialization.data(withJSONObject: json)
        http.responses = [HTTPResponse(statusCode: 200, headers: [:], body: body)]
        let service = SDKCipherService(httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { "token" })
        await #expect(throws: SDKPasskeyWriteError.confirmedButUnreadable) {
            _ = try await service.savePasskeyResponse(.fixture(id: failure == "foreign-update-id" ? "expected" : nil))
        }
    }

    @Test(arguments: [false, true])
    func passkeyCreateAndOmittedUpdateIDPreserveExistingRequestWireAndRedirectPolicy(_ update: Bool) async throws {
        let http = MockHTTPClient()
        var json: [String: Any] = ["type": 1, "name": "encrypted-name", "login": ["username": "encrypted-user"]]
        if !update { json["id"] = "created" }
        http.responses = [
            HTTPResponse(statusCode: 200, headers: [:], body: try JSONSerialization.data(withJSONObject: json)),
        ]
        let service = SDKCipherService(httpClient: http, apiURL: apiURL, userID: "user-1", accessToken: { "token" })
        let response = try await service.savePasskeyResponse(.fixture(id: update ? "existing" : nil))
        #expect(response.id == (update ? "existing" : "created"))
        let request = try #require(http.calls.first?.request)
        #expect(request.method == (update ? .put : .post) && request.redirectPolicy == .reject)
        #expect(request.url.path == (update ? "/api/ciphers/existing" : "/api/ciphers"))
        #expect(request.headers["Authorization"] == "Bearer token")
    }
}
