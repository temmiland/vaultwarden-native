import Foundation
import Networking

/// Applies the live runtime lifetime to the existing shared HTTP transport. This is not another
/// token store or networking stack; each request is registered, cancelled and checked by Data.
public struct SessionHTTPClient: HTTPClient {
    private let runtime: SessionRuntime
    private let base: any HTTPClient

    public init(runtime: SessionRuntime, base: any HTTPClient) {
        self.runtime = runtime
        self.base = base
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await runtime.perform { [base] in try await base.send(request) }
    }

    public func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        try await runtime.perform { [base] in try await base.upload(request, fromFile: fileURL) }
    }

    public func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        try await runtime.perform { [base] in try await base.download(request, to: destinationURL) }
    }
}
