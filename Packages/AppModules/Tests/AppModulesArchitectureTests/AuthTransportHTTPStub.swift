import Foundation
import Networking

/// Test-only synchronous recording behind a lock; no live network or filesystem fallback.
final class AuthTransportHTTPStub: HTTPClient, @unchecked Sendable {
    private enum FixtureError: Error { case unplannedRequest, unsupportedTransfer }
    private let lock = NSLock()
    private var storedRequests: [HTTPRequest] = []
    private var storedResponses: [HTTPResponse] = []

    var requests: [HTTPRequest] { lock.withLock { storedRequests } }
    var responses: [HTTPResponse] {
        get { lock.withLock { storedResponses } }
        set { lock.withLock { storedResponses = newValue } }
    }

    var lastRequest: HTTPRequest? { requests.last }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            storedRequests.append(request)
            guard !storedResponses.isEmpty else { throw FixtureError.unplannedRequest }
            return storedResponses.removeFirst()
        }
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        throw FixtureError.unsupportedTransfer
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        throw FixtureError.unsupportedTransfer
    }

    func lastRequestFormFields() -> [String: String] {
        guard let body = lastRequest?.body, let string = String(data: body, encoding: .utf8) else { return [:] }
        return string.split(separator: "&").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            result[name] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
    }
}
