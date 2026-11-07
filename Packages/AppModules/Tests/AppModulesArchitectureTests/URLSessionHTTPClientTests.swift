import Foundation
@testable import Networking
import Testing

/// Ported from the removed NetworkingKit package; exercises the production transport now.
@Suite
struct URLSessionHTTPClientTests {
    @Test
    func redirectsAreRejectedByDefault() {
        #expect(HTTPRequest(url: URL(string: "https://fixture.example.com")!).redirectPolicy == .reject)
    }

    @Test
    func explicitCrossOriginGetRedirectStripsCredentialHeaders() throws {
        let original = HTTPRequest(
            url: URL(string: "https://vault.example.com/api/public")!,
            headers: ["Authorization": "Bearer synthetic", "Cookie": "session=synthetic"],
            redirectPolicy: .follow
        )
        var redirected = URLRequest(url: URL(string: "https://cdn.example.net/public")!)
        redirected.httpMethod = "GET"
        redirected.setValue("Bearer synthetic", forHTTPHeaderField: "Authorization")
        redirected.setValue("session=synthetic", forHTTPHeaderField: "Cookie")
        let safe = try #require(CredentialSafeRedirectPolicy.request(
            from: original.url,
            redirecting: redirected,
            original: original
        ))
        #expect(safe.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(safe.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test
    func redirectFollowRejectsBodiesAndHTTPSDowngrades() {
        let original = HTTPRequest(
            url: URL(string: "https://vault.example.com/api")!,
            method: .post,
            body: Data("synthetic secret".utf8),
            redirectPolicy: .follow
        )
        var redirected = URLRequest(url: URL(string: "https://other.example.net/api")!)
        redirected.httpMethod = "GET"
        #expect(CredentialSafeRedirectPolicy.request(
            from: original.url,
            redirecting: redirected,
            original: original
        ) == nil)

        let publicGet = HTTPRequest(url: original.url, redirectPolicy: .follow)
        #expect(CredentialSafeRedirectPolicy.request(
            from: publicGet.url, redirecting: redirected, original: publicGet, hasFileBody: true
        ) == nil)
        var downgrade = URLRequest(url: URL(string: "http://other.example.net/api")!)
        downgrade.httpMethod = "GET"
        #expect(CredentialSafeRedirectPolicy.request(
            from: publicGet.url,
            redirecting: downgrade,
            original: publicGet
        ) == nil)
    }

    @Test
    func explicitSameOriginBodylessGetRedirectPreservesPublicRequest() throws {
        let original = HTTPRequest(url: URL(string: "https://vault.example.com/api")!, redirectPolicy: .follow)
        var redirected = URLRequest(url: URL(string: "https://vault.example.com/new")!)
        redirected.httpMethod = "GET"
        let safe = try #require(CredentialSafeRedirectPolicy.request(
            from: original.url,
            redirecting: redirected,
            original: original
        ))
        #expect(safe.url == redirected.url)
    }

    @Test
    func sendReturnsStatusHeadersAndUnmodifiedBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPClient(session: session)

        let response = try await transport.send(HTTPRequest(url: URL(string: "https://fixture.example.com/api/sync")!))

        #expect(response.statusCode == 200)
        #expect(response.isSuccess)
        #expect(response.headers.first { $0.key.lowercased() == "x-test" }?.value == "yes")
        #expect(response.body == Data("{\"ok\":true}".utf8))
    }

    @Test
    func sendStopsWhenAChunkedResponseExceedsItsBodyLimit() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPClient(session: session)
        let request = HTTPRequest(
            url: URL(string: "https://fixture.example.com/oversized")!,
            maximumResponseBytes: 8
        )

        await #expect(throws: HTTPResponseBodyError.exceedsLimit(maximumBytes: 8)) {
            try await transport.send(request)
        }
    }

    @Test
    func downloadPublishesTheExactLimitWithRestrictivePermissions() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPClient(session: session)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result")
        let expected = Data("{\"ok\":true}".utf8)
        let response = try await transport.download(
            HTTPRequest(url: URL(string: "https://fixture.example.com/file")!, maximumResponseBytes: expected.count),
            to: destination
        )
        #expect(response.statusCode == 200)
        #expect(try Data(contentsOf: destination) == expected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["result"])
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test(arguments: ["oversized", "oversized-known"])
    func downloadLimitRejectsAdvertisedOrChunkedOversizeAndPreservesDestination(path: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPClient(session: session)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result")
        let old = Data("old".utf8)
        try old.write(to: destination)
        await #expect(throws: HTTPResponseBodyError.exceedsLimit(maximumBytes: 8)) {
            try await transport.download(
                HTTPRequest(url: URL(string: "https://fixture.example.com/\(path)")!, maximumResponseBytes: 8),
                to: destination
            )
        }
        #expect(try Data(contentsOf: destination) == old)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["result"])
    }

    @Test
    func uploadCompletionAndCancellationRaceTerminatesWithOneOutcome() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPClient(session: session)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("synthetic upload".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        for _ in 0 ..< 20 {
            let operation = Task {
                try await transport.upload(
                    HTTPRequest(url: URL(string: "https://fixture.example.com/complete")!, method: .post),
                    fromFile: file
                )
            }
            await Task.yield()
            operation.cancel()
            do {
                // Completion may win; an acknowledged response must not be relabelled as rollback.
                #expect(try await operation.value.statusCode == 200)
            } catch is CancellationError {} catch {
                Issue.record("Unexpected upload cancellation/response outcome")
            }
        }
    }

    @Test
    func uploadStopsWhenAResponseExceedsItsBodyLimit() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPClient(session: session)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("synthetic upload".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let request = HTTPRequest(
            url: URL(string: "https://fixture.example.com/oversized")!,
            method: .put,
            maximumResponseBytes: 8
        )

        await #expect(throws: HTTPResponseBodyError.exceedsLimit(maximumBytes: 8)) {
            try await transport.upload(request, fromFile: fileURL)
        }
    }
}

/// Immutable response, no shared mutable global handler and no real network traffic.
private final class TransportFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: url.path == "/oversized-known" ? ["Content-Length": "64"] : ["X-Test": "yes"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = url.path.hasPrefix("/oversized") ? Data(repeating: 65, count: 64) : Data("{\"ok\":true}".utf8)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
