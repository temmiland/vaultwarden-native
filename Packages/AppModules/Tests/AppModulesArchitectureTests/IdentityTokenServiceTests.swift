@testable import Data
import Foundation
import Networking
import Testing

@Suite
struct IdentityTokenServiceTests {
    private let identityURL = URL(string: "https://vault.example.com/identity")!
    private let device = DeviceInfo(identifier: "device-123", name: "Test Mac")

    @Test
    func passwordGrantBuildsExpectedFormBody() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [successResponse()]
        let service = DefaultIdentityTokenService(httpClient: http)

        _ = try await service.requestToken(
            identityURL: identityURL,
            username: "user@example.com",
            passwordHash: "hashed-password==",
            device: device,
            twoFactor: nil
        )

        let request = try #require(http.lastRequest)
        #expect(request.url == identityURL.appendingPathComponent("connect/token"))
        #expect(request.method == .post)
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(request.redirectPolicy == .reject)

        let fields = http.lastRequestFormFields()
        #expect(fields["grant_type"] == "password")
        #expect(fields["username"] == "user@example.com")
        #expect(fields["password"] == "hashed-password==")
        #expect(fields["scope"] == "api offline_access")
        #expect(fields["client_id"] == "connector")
        #expect(fields["deviceIdentifier"] == "device-123")
        #expect(fields["deviceType"] == "7")
        #expect(fields["twoFactorToken"] == nil)
    }

    @Test
    func passwordGrantIncludesTwoFactorFieldsWhenProvided() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [successResponse()]
        let service = DefaultIdentityTokenService(httpClient: http)

        _ = try await service.requestToken(
            identityURL: identityURL,
            username: "user@example.com",
            passwordHash: "hash",
            device: device,
            twoFactor: TwoFactorSubmission(code: "123456", provider: 0, remember: true)
        )

        let fields = http.lastRequestFormFields()
        #expect(fields["twoFactorToken"] == "123456")
        #expect(fields["twoFactorProvider"] == "0")
        #expect(fields["twoFactorRemember"] == "1")
    }

    @Test
    func successResponseIsParsedIncludingMixedCaseFields() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [successResponse()]
        let service = DefaultIdentityTokenService(httpClient: http)

        let outcome = try await service.requestToken(
            identityURL: identityURL,
            username: "user@example.com",
            passwordHash: "hash",
            device: device,
            twoFactor: nil
        )

        guard case let .success(response) = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
        #expect(response.accessToken == "access-token-value")
        #expect(response.refreshToken == "refresh-token-value")
        #expect(response.key == "encrypted-user-key")
        #expect(response.privateKey == "encrypted-private-key")
        #expect(response.expiresIn == 3600)
    }

    @Test
    func twoFactorRequiredErrorIsDetected() async throws {
        let http = AuthTransportHTTPStub()
        let body = Data(#"""
        {
            "error": "invalid_grant",
            "error_description": "Two factor required.",
            "TwoFactorProviders": [0, 1]
        }
        """#.utf8)
        http.responses = [HTTPResponse(statusCode: 400, headers: [:], body: body)]
        let service = DefaultIdentityTokenService(httpClient: http)

        let outcome = try await service.requestToken(
            identityURL: identityURL,
            username: "user@example.com",
            passwordHash: "hash",
            device: device,
            twoFactor: nil
        )

        guard case let .twoFactorRequired(providers) = outcome else {
            Issue.record("Expected twoFactorRequired, got \(outcome)")
            return
        }
        #expect(providers == [0, 1])
    }

    /// Regression test: real Vaultwarden (unlike the OpenAPI-documented official server) encodes
    /// `TwoFactorProviders` as an array of *string* numbers, not JSON integers. This exact body was
    /// captured from a live Vaultwarden instance during manual testing - decoding used to silently
    /// fail (`try?` swallowing the type mismatch) and fall through to a generic "Login failed",
    /// never reaching the two-factor screen at all.
    @Test
    func twoFactorRequiredIsDetectedWhenVaultwardenSendsProvidersAsStrings() async throws {
        let http = AuthTransportHTTPStub()
        let body = Data(#"""
        {"error":"invalid_grant","error_description":"Two factor required.","TwoFactorProviders":["0"],"TwoFactorProviders2":{"0":null},"MasterPasswordPolicy":{"Object":"masterPasswordPolicy"}}
        """#.utf8)
        http.responses = [HTTPResponse(statusCode: 400, headers: [:], body: body)]
        let service = DefaultIdentityTokenService(httpClient: http)

        let outcome = try await service.requestToken(
            identityURL: identityURL,
            username: "user@example.com",
            passwordHash: "hash",
            device: device,
            twoFactor: nil
        )

        guard case let .twoFactorRequired(providers) = outcome else {
            Issue.record("Expected twoFactorRequired, got \(outcome)")
            return
        }
        #expect(providers == [0])
    }

    @Test
    func invalidCredentialsAreReportedAsFailureNotTwoFactor() async throws {
        let http = AuthTransportHTTPStub()
        let body = Data(#"""
        {
            "error": "invalid_grant",
            "error_description": "Username or password is incorrect."
        }
        """#.utf8)
        http.responses = [HTTPResponse(statusCode: 400, headers: [:], body: body)]
        let service = DefaultIdentityTokenService(httpClient: http)

        let outcome = try await service.requestToken(
            identityURL: identityURL,
            username: "user@example.com",
            passwordHash: "hash",
            device: device,
            twoFactor: nil
        )

        guard case let .failure(message) = outcome else {
            Issue.record("Expected failure, got \(outcome)")
            return
        }
        #expect(message == "Username or password is incorrect.")
    }

    @Test
    func refreshGrantBuildsMinimalFormBody() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [successResponse()]
        let service = DefaultIdentityTokenService(httpClient: http)

        _ = try await service.refreshToken(identityURL: identityURL, refreshToken: "the-refresh-token")

        let fields = http.lastRequestFormFields()
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["client_id"] == "connector")
        #expect(fields["refresh_token"] == "the-refresh-token")
    }

    @Test
    func refreshInvalidGrantIsClassifiedAsSessionRejection() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [HTTPResponse(
            statusCode: 400,
            headers: [:],
            body: Data(#"{"error":"invalid_grant"}"#.utf8)
        )]
        let service = DefaultIdentityTokenService(httpClient: http)

        let outcome = try await service.refreshToken(identityURL: identityURL, refreshToken: "revoked")

        guard case .rejected = outcome else {
            Issue.record("Expected rejected, got \(outcome)")
            return
        }
    }

    @Test(arguments: [429, 500, 503])
    func transientRefreshHTTPFailuresAreNotClassifiedAsSessionRejection(_ statusCode: Int) async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [
            HTTPResponse(statusCode: statusCode, headers: [:], body: Data(#"{"error":"invalid_grant"}"#.utf8)),
        ]
        let service = DefaultIdentityTokenService(httpClient: http)

        let outcome = try await service.refreshToken(identityURL: identityURL, refreshToken: "still-valid")

        guard case .retryable = outcome else {
            Issue.record("Expected retryable failure, got \(outcome)")
            return
        }
    }

    @Test
    func rawLoginDiagnosticsCannotBecomeUserFacingErrorMessages() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [HTTPResponse(statusCode: 400, headers: [:], body: Data(
            #"{"error":"server_error","error_description":"fake-password-and-private-diagnostic"}"#.utf8
        ))]
        let outcome = try await DefaultIdentityTokenService(httpClient: http).requestToken(
            identityURL: identityURL, username: "test@example.com", passwordHash: "fake-hash", device: device,
            twoFactor: nil
        )
        guard case let .failure(message) = outcome else { Issue.record("Expected stable login failure"); return }
        #expect(!message.contains("fake-password"))
        #expect(!message.contains("private-diagnostic"))
    }

    @Test(arguments: [429, 500, 503])
    func transientLoginStatusesCannotBeMistakenForTwoFactorChallenges(_ status: Int) async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [HTTPResponse(statusCode: status, headers: [:], body: Data(
            #"{"error":"invalid_grant","TwoFactorProviders":[0]}"#.utf8
        ))]
        let outcome = try await DefaultIdentityTokenService(httpClient: http).requestToken(
            identityURL: identityURL, username: "test@example.com", passwordHash: "fake-hash", device: device,
            twoFactor: nil
        )
        guard case .failure = outcome else { Issue.record("Expected retryable login failure, not navigation to 2FA"); return }
    }

    private func successResponse() -> HTTPResponse {
        let body = Data(#"""
        {
            "access_token": "access-token-value",
            "expires_in": 3600,
            "token_type": "Bearer",
            "refresh_token": "refresh-token-value",
            "Key": "encrypted-user-key",
            "PrivateKey": "encrypted-private-key",
            "Kdf": 0,
            "KdfIterations": 600000
        }
        """#.utf8)
        return HTTPResponse(statusCode: 200, headers: [:], body: body)
    }
}
