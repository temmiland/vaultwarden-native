import Domain
import Foundation
import Networking

public protocol IdentityTokenService: TokenRefreshing {
    func requestToken(
        identityURL: URL,
        username: String,
        passwordHash: String,
        device: DeviceInfo,
        twoFactor: TwoFactorSubmission?
    ) async throws -> TokenRequestOutcome
}

public struct DefaultIdentityTokenService: IdentityTokenService {
    private let httpClient: any HTTPClient

    public init(httpClient: any HTTPClient) { self.httpClient = httpClient }

    public func requestToken(
        identityURL: URL,
        username: String,
        passwordHash: String,
        device: DeviceInfo,
        twoFactor: TwoFactorSubmission?
    ) async throws -> TokenRequestOutcome {
        try Task.checkCancellation()
        guard ServerURLPolicy.isPermitted(identityURL) else { throw ServerEnvironmentError.invalidBaseURL }
        let body = TokenRequestBuilder.passwordGrant(
            username: username,
            passwordHash: passwordHash,
            device: device,
            twoFactor: twoFactor
        )
        return try await send(body: body, identityURL: identityURL)
    }

    public func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome {
        try Task.checkCancellation()
        guard ServerURLPolicy.isPermitted(identityURL) else { throw ServerEnvironmentError.invalidBaseURL }
        return try await DefaultTokenRefreshService(httpClient: httpClient).refreshToken(
            identityURL: identityURL,
            refreshToken: refreshToken
        )
    }

    private func send(body: Foundation.Data, identityURL: URL) async throws -> TokenRequestOutcome {
        let url = identityURL.appendingPathComponent("connect/token")
        let request = HTTPRequest(
            url: url,
            method: .post,
            headers: [
                "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
                "Accept": "application/json",
            ],
            body: body,
            redirectPolicy: .reject
        )

        let response = try await httpClient.send(request)
        try Task.checkCancellation()
        let decoder = FlexibleKeyDecoding.makeDecoder()

        if response.isSuccess {
            guard let success = try? decoder.decode(TokenSuccessResponse.self, from: response.body),
                  !success.accessToken.isEmpty, success.expiresIn > 0,
                  success.tokenType.lowercased() == "bearer" else {
                return .failure(message: "The server returned an unrecognized response.")
            }
            return .success(success)
        }

        // Transient status is authoritative, even when a server/proxy supplied an OAuth body.
        if response.statusCode == 429 { return .failure(message: "The server is busy. Please try again shortly.") }
        if (500 ... 599).contains(response.statusCode) {
            return .failure(message: "The server is temporarily unavailable. Please try again.")
        }
        if [400, 401].contains(response.statusCode),
           let errorBody = try? decoder.decode(TokenErrorResponse.self, from: response.body) {
            if let providers = errorBody.twoFactorProviders, !providers.isEmpty {
                return .twoFactorRequired(providers: providers)
            }
            if errorBody.error?.lowercased() == "invalid_grant" {
                return .failure(message: "Username or password is incorrect.")
            }
            // Raw server diagnostics may contain secrets or internal details, never UI strings.
            return .failure(message: "Login failed. Please check your details and try again.")
        }
        return .failure(message: "Login failed. Please try again.")
    }
}
