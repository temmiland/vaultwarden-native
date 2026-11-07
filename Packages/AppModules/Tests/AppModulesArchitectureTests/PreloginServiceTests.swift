@testable import Data
import Domain
import Foundation
import Networking
import Testing

@Suite
struct PreloginServiceTests {
    @Test
    func fetchKdfPostsEmailToPreloginEndpoint() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [
            HTTPResponse(
                statusCode: 200,
                headers: [:],
                body: Data(
                    #"{"kdf":0,"kdfIterations":600000,"kdfMemory":null,"kdfParallelism":null,"salt":"user@example.com"}"#.utf8
                )
            ),
        ]
        let service = DefaultPreloginService(httpClient: http)
        let identityURL = URL(string: "https://vault.example.com/identity")!

        _ = try await service.fetchKdf(email: "user@example.com", identityURL: identityURL)

        let request = try #require(http.lastRequest)
        #expect(request.url == identityURL.appendingPathComponent("accounts/prelogin"))
        #expect(request.method == .post)
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.redirectPolicy == .reject)

        let body = try #require(request.body)
        let decoded = try JSONDecoder().decode(PreloginRequestBody.self, from: body)
        #expect(decoded.email == "user@example.com")
    }

    @Test
    func fetchKdfResolvesPBKDF2Response() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [
            HTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"kdf":0,"kdfIterations":600000}"#.utf8)),
        ]
        let service = DefaultPreloginService(httpClient: http)

        let kdf = try await service.fetchKdf(email: "a@b.com", identityURL: URL(string: "https://example.com/identity")!)

        guard case let .pbkdf2(iterations) = kdf else {
            Issue.record("Expected pbkdf2, got \(kdf)")
            return
        }
        #expect(iterations == 600_000)
    }

    @Test
    func fetchKdfResolvesArgon2idResponse() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [
            HTTPResponse(
                statusCode: 200,
                headers: [:],
                body: Data(#"{"kdf":1,"kdfIterations":3,"kdfMemory":64,"kdfParallelism":4}"#.utf8)
            ),
        ]
        let service = DefaultPreloginService(httpClient: http)

        let kdf = try await service.fetchKdf(email: "a@b.com", identityURL: URL(string: "https://example.com/identity")!)

        guard case let .argon2id(iterations, memory, parallelism) = kdf else {
            Issue.record("Expected argon2id, got \(kdf)")
            return
        }
        #expect(iterations == 3)
        #expect(memory == 64)
        #expect(parallelism == 4)
    }

    @Test
    func fetchKdfThrowsOnServerError() async {
        let http = AuthTransportHTTPStub()
        http.responses = [HTTPResponse(statusCode: 500, headers: [:], body: Data())]
        let service = DefaultPreloginService(httpClient: http)

        await #expect(throws: PreloginError.self) {
            _ = try await service.fetchKdf(email: "a@b.com", identityURL: URL(string: "https://example.com/identity")!)
        }
    }
}
