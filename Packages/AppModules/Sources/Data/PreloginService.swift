import Domain
import Foundation
import Networking

public enum PreloginError: Error, Sendable, Equatable {
    case invalidResponse
    case server(statusCode: Int)
}

public struct DefaultPreloginService: PreloginService {
    private let httpClient: any HTTPClient

    public init(httpClient: any HTTPClient) { self.httpClient = httpClient }

    public func fetchKdf(email: String, identityURL: URL) async throws -> KeyDerivationParameters {
        try Task.checkCancellation()
        guard ServerURLPolicy.isPermitted(identityURL) else { throw ServerEnvironmentError.invalidBaseURL }
        let url = identityURL.appendingPathComponent("accounts/prelogin")
        let body = try JSONEncoder().encode(PreloginRequestBody(email: email))
        let request = HTTPRequest(
            url: url,
            method: .post,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: body,
            redirectPolicy: .reject
        )

        let response = try await httpClient.send(request)
        try Task.checkCancellation()
        guard response.isSuccess else {
            throw PreloginError.server(statusCode: response.statusCode)
        }

        guard let decoded = try? FlexibleKeyDecoding.makeDecoder().decode(PreloginResponseBody.self, from: response.body) else {
            throw PreloginError.invalidResponse
        }
        return try decoded.resolvedParameters
    }
}
