import Data
import Foundation
import Networking
import Testing

/// Pure wire/classifier fixtures, no SDK, real transport, Keychain or test-time sleeps.
@Suite
struct TokenRefreshServiceTests {
    private let identityURL = URL(string: "https://vault.example.com/reverse-proxy/identity")!

    @Test
    func refreshUsesOneConnectorFormAndRejectsRedirects() async throws {
        let http = TokenHTTPFixture(
            status: 200,
            body: #"{"AccessToken":"fake-access","RefreshToken":"fake-refresh","ExpiresIn":3600,"TokenType":"Bearer"}"#
        )
        let service = DefaultTokenRefreshService(httpClient: http)
        let outcome = try await service.refreshToken(identityURL: identityURL, refreshToken: "fake refresh&=+")
        let request = try #require(await http.lastRequest)
        #expect(request.url == identityURL.appendingPathComponent("connect/token"))
        #expect(request.method == .post)
        #expect(request.redirectPolicy == .reject)
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(request.headers["Accept"] == "application/json")
        #expect(String(decoding: try #require(request.body), as: UTF8.self) ==
            "grant_type=refresh_token&client_id=connector&refresh_token=fake%20refresh%26%3D%2B")
        #expect(outcome == .success(RefreshedTokenPayload(
            accessToken: "fake-access",
            refreshToken: "fake-refresh",
            expiresIn: 3600,
            tokenType: "Bearer"
        )))
    }

    @Test(arguments: [400, 401])
    func onlyExplicitOAuthRejectionOnAnAuthStatusExpires(_ status: Int) async throws {
        let service = DefaultTokenRefreshService(
            httpClient: TokenHTTPFixture(status: status, body: #"{"error":"invalid_grant"}"#)
        )
        #expect(try await service.refreshToken(identityURL: identityURL, refreshToken: "fake-refresh") == .rejected)
    }

    @Test(arguments: [429, 500, 503, 302, 404])
    func transientAndNonAuthStatusesWinOverMisleadingOAuthBodies(_ status: Int) async throws {
        let http = TokenHTTPFixture(
            status: status,
            body: #"{"error":"invalid_grant","error_description":"fake-private-diagnostic"}"#,
            headers: ["retry-after": "60"]
        )
        let outcome = try await DefaultTokenRefreshService(httpClient: http).refreshToken(
            identityURL: identityURL,
            refreshToken: "fake-refresh"
        )
        #expect(outcome == .retryable(.http(statusCode: status, retryAfter: 60)))
        #expect(!String(reflecting: outcome).contains("fake-private-diagnostic"))
    }

    @Test(arguments: ["", "not-json", #"{"error":"server_error"}"#, #"{"error_description":"fake-password"}"#])
    func a401WithoutExplicitRejectionRemainsRetryable(_ body: String) async throws {
        let outcome = try await DefaultTokenRefreshService(httpClient: TokenHTTPFixture(status: 401, body: body))
            .refreshToken(identityURL: identityURL, refreshToken: "fake-refresh")
        guard case .retryable = outcome else { Issue.record("Expected retryable classification"); return }
        #expect(!String(describing: outcome).contains("fake-password"))
    }

    @Test(arguments: [
        #"{"error":"invalid_grant","TwoFactorProviders":[0]}"#,
        #"{"error":"invalid_grant","TwoFactorProviders":["0"]}"#,
        #"{"error":"invalid_grant","TwoFactorProviders":{"malformed":true}}"#,
    ])
    func unexpectedRefreshChallengesAreNotDefinitiveRejections(_ body: String) async throws {
        let outcome = try await DefaultTokenRefreshService(httpClient: TokenHTTPFixture(status: 400, body: body))
            .refreshToken(identityURL: identityURL, refreshToken: "fake-refresh")
        #expect(outcome == .retryable(.oauthFailure))
    }

    @Test(arguments: [
        #"{}"#,
        #"{"access_token":"","expires_in":3600}"#,
        #"{"access_token":"fake-access","expires_in":0}"#,
        #"{"access_token":"fake-access","expires_in":-1}"#,
        #"{"access_token":"fake-access","expires_in":0.5}"#,
        #"{"access_token":"fake-access","expires_in":3600,"refresh_token":""}"#,
        #"{"access_token":"fake-access","expires_in":3600,"token_type":"not-bearer"}"#,
    ])
    func malformedSuccessPayloadsCannotPoisonTheTokenStore(_ body: String) async throws {
        let outcome = try await DefaultTokenRefreshService(httpClient: TokenHTTPFixture(status: 200, body: body))
            .refreshToken(identityURL: identityURL, refreshToken: "fake-refresh")
        #expect(outcome == .retryable(.malformedResponse))
    }

    @Test
    func aMissingRefreshTokenIsPreservedAsMissingForTheCoordinator() async throws {
        let outcome = try await DefaultTokenRefreshService(httpClient: TokenHTTPFixture(
            status: 200,
            body: #"{"access_token":"fake-access","expires_in":3600}"#
        ))
        .refreshToken(identityURL: identityURL, refreshToken: "fake-refresh")
        #expect(
            outcome == .success(RefreshedTokenPayload(accessToken: "fake-access", refreshToken: nil, expiresIn: 3600))
        )
    }

    @Test
    func retryAfterHandlesHTTPDatesAndRejectsNonfiniteOrNegativeDelays() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "1994-11-15T08:12:00Z"))
        #expect(HTTPRetryAfter.value(from: ["Retry-After": "Tue, 15 Nov 1994 08:12:31 GMT"], now: now) == 31)
        #expect(HTTPRetryAfter.value(from: ["Retry-After": "Tue, 15 Nov 1994 08:11:00 GMT"], now: now) == 0)
        for value in ["-1", "nan", "inf", "1e999", "not-a-date"] {
            #expect(HTTPRetryAfter.value(from: ["Retry-After": value], now: now) == nil)
        }
        #expect(HTTPRetryAfter.value(from: [:], now: now) == nil)
    }

    @Test
    func typedRefreshDescriptionsNeverExposeTokens() {
        let payload = RefreshedTokenPayload(
            accessToken: "fake-secret-access",
            refreshToken: "fake-secret-refresh",
            expiresIn: 3600
        )
        for description in [String(reflecting: payload), String(reflecting: TokenRefreshOutcome.success(payload))] {
            #expect(!description.contains("fake-secret"))
        }
    }
}

private actor TokenHTTPFixture: HTTPClient {
    private let response: HTTPResponse
    private(set) var lastRequest: HTTPRequest?
    init(status: Int, body: String, headers: [String: String] = [:]) {
        response = HTTPResponse(statusCode: status, headers: headers, body: Foundation.Data(body.utf8))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse { lastRequest = request; return response }
    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse { throw CancellationError() }
    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse { throw CancellationError(
    ) }
}
