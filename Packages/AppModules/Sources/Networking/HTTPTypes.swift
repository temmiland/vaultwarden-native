import Foundation

public enum HTTPResponseBodyLimit {
    /// JSON control endpoints return metadata, never attachment payloads.
    public static let standard = 4 * 1024 * 1024
    /// Sync contains the full encrypted vault; cap it separately from small control responses.
    public static let vaultSync = 64 * 1024 * 1024
    /// Local safety cap for encrypted attachment downloads, not a server quota or peak-RAM guarantee.
    public static let fileDownload = 64 * 1024 * 1024
}

public enum HTTPResponseBodyError: Error, Sendable, Equatable {
    case exceedsLimit(maximumBytes: Int)
}

public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    public enum RedirectPolicy: Sendable, Equatable {
        /// Follow bodyless GET redirects only; cross-origin redirects lose credentials and HTTPS
        /// redirects may not downgrade to HTTP.
        case follow
        /// Reject redirects for endpoints whose response must come from the configured origin.
        case reject
    }

    public var url: URL
    public var method: Method
    public var headers: [String: String]
    public var body: Data?
    public var redirectPolicy: RedirectPolicy
    public var maximumResponseBytes: Int

    public init(
        url: URL,
        method: Method = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        redirectPolicy: RedirectPolicy = .reject,
        maximumResponseBytes: Int = HTTPResponseBodyLimit.standard
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.redirectPolicy = redirectPolicy
        self.maximumResponseBytes = max(0, maximumResponseBytes)
    }
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200 ..< 300).contains(statusCode) }

    public func requireSuccess() throws {
        guard isSuccess else { throw HTTPStatusError(response: self) }
    }
}

public struct HTTPFileResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]

    public init(statusCode: Int, headers: [String: String]) {
        self.statusCode = statusCode
        self.headers = headers
    }
}

public enum HTTPFileTransferError: Error, Sendable, Equatable {
    case invalidDestination
    case cleanupFailed
}

/// A status failure containing only transport metadata. Server response bodies and headers may
/// contain secrets, so they are discarded at this boundary.
public struct HTTPStatusError: Error, Sendable, Equatable {
    public let statusCode: Int
    public let retryAfter: TimeInterval?

    public init(response: HTTPResponse) {
        statusCode = response.statusCode
        retryAfter = HTTPRetryAfter.value(from: response.headers)
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse
    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse
}
