import Foundation
import Networking

/// Records every request it's sent and returns pre-programmed responses in order (or throws a
/// pre-programmed error). Good enough for the request-building / response-parsing tests here -
/// nothing in this package makes live network calls.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []
    var responses: [HTTPResponse] = []
    var errorToThrow: Error?

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if let errorToThrow { throw errorToThrow }
        guard !responses.isEmpty else {
            return HTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        return responses.removeFirst()
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        var request = request
        request.body = try Data(contentsOf: fileURL)
        return try await send(request)
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        let response = try await send(request)
        try response.requireSuccess()
        try response.body.write(to: destinationURL)
        return HTTPFileResponse(statusCode: response.statusCode, headers: response.headers)
    }

    var lastRequest: HTTPRequest? { requests.last }

    /// Decodes the last sent request's form-urlencoded body into a name -> value dictionary.
    func lastRequestFormFields() -> [String: String] {
        guard let body = requests.last?.body, let bodyString = String(data: body, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for pair in bodyString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            result[name] = value
        }
        return result
    }
}
