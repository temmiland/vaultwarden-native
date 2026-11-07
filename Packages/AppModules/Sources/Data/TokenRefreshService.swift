import Foundation
import Networking

/// Only token rotation data crosses this port, never SDK models, raw server errors or keys.
public struct RefreshedTokenPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let tokenType: String?

    public init(accessToken: String, refreshToken: String?, expiresIn: Int, tokenType: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
    }

    public var isValid: Bool {
        !accessToken.isEmpty && (refreshToken == nil || refreshToken?.isEmpty == false) &&
            expiresIn > 0 && (tokenType == nil || tokenType?.lowercased() == "bearer")
    }

    public var description: String { "RefreshedTokenPayload(<redacted>)" }
    public var debugDescription: String { description }
}

public enum TokenRefreshRetryReason: Sendable, Equatable {
    case transport
    case cancelled
    case malformedResponse
    case oauthFailure
    case http(statusCode: Int, retryAfter: TimeInterval?)
}

public enum TokenRefreshOutcome: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case success(RefreshedTokenPayload)
    case rejected
    case retryable(TokenRefreshRetryReason)

    public var description: String { "TokenRefreshOutcome(<redacted>)" }
    public var debugDescription: String { description }
}

public protocol TokenRefreshing: Sendable {
    func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome
}

/// Shared live transport/classifier for app AND extension. Transient status wins over any
/// misleading OAuth body; only explicit invalid_grant on 400/401 is a definitive rejection.
public struct DefaultTokenRefreshService: TokenRefreshing {
    private let httpClient: any HTTPClient
    private let now: @Sendable () -> Date

    public init(httpClient: any HTTPClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.httpClient = httpClient
        self.now = now
    }

    public func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome {
        try Task.checkCancellation()
        let request = HTTPRequest(
            url: identityURL.appendingPathComponent("connect/token"),
            method: .post,
            headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8", "Accept": "application/json"],
            body: OAuthClientConfiguration.refreshGrantBody(refreshToken: refreshToken),
            redirectPolicy: .reject
        )
        let response = try await httpClient.send(request)
        try Task.checkCancellation()
        let retryAfter = HTTPRetryAfter.value(from: response.headers, now: now())
        if response.statusCode == 429 || (500 ... 599).contains(response.statusCode) {
            return .retryable(.http(statusCode: response.statusCode, retryAfter: retryAfter))
        }
        let decoder = FlexibleKeyDecoding.makeDecoder()
        if response.isSuccess {
            guard let wire = try? decoder.decode(SuccessPayload.self, from: response.body) else {
                return .retryable(.malformedResponse)
            }
            let payload = RefreshedTokenPayload(
                accessToken: wire.accessToken,
                refreshToken: wire.refreshToken,
                expiresIn: wire.expiresIn,
                tokenType: wire.tokenType
            )
            return payload.isValid ? .success(payload) : .retryable(.malformedResponse)
        }
        if [400, 401].contains(response.statusCode),
           let error = try? decoder.decode(ErrorPayload.self, from: response.body) {
            if error.error?.lowercased() == "invalid_grant", !error.hasChallenge { return .rejected }
            return .retryable(.oauthFailure)
        }
        return .retryable(.http(statusCode: response.statusCode, retryAfter: retryAfter))
    }

    private struct SuccessPayload: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let tokenType: String?
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let hasChallenge: Bool
        enum CodingKeys: String, CodingKey { case error, twoFactorProviders }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            error = try values.decodeIfPresent(String.self, forKey: .error)
            if let providers = try? values.decode([Int].self, forKey: .twoFactorProviders) {
                hasChallenge = !providers.isEmpty
            } else if let providers = try? values.decode([String].self, forKey: .twoFactorProviders) {
                hasChallenge = !providers.isEmpty
            } else if values.contains(.twoFactorProviders) {
                // A malformed challenge is not proof of a rejected refresh token either.
                hasChallenge = try !values.decodeNil(forKey: .twoFactorProviders)
            } else { hasChallenge = false }
        }
    }
}
