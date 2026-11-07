@testable import Data
import Domain
import Foundation
import Networking
import Testing

@Suite
struct AuthTransportBoundaryTests {
    private let device = DeviceInfo(identifier: "fixture-device", name: "Fixture")

    @Test(arguments: ["http://vault.example.com", "https://user:password@vault.example.com/identity",
                      "https://vault.example.com/identity?token=fixture",
                      "https://vault.example.com/identity#fragment"])
    func credentialTransportsRejectUnsafeServersBeforeSendingAnything(_ value: String) async throws {
        let identity = try #require(URL(string: value))
        let http = AuthTransportHTTPStub()
        await #expect(throws: ServerEnvironmentError.invalidBaseURL) {
            _ = try await DefaultPreloginService(httpClient: http).fetchKdf(
                email: "fixture@example.com",
                identityURL: identity
            )
        }
        let tokens = DefaultIdentityTokenService(httpClient: http)
        await #expect(throws: ServerEnvironmentError.invalidBaseURL) {
            _ = try await tokens.requestToken(
                identityURL: identity,
                username: "fixture@example.com",
                passwordHash: "fixture-hash",
                device: device,
                twoFactor: nil
            )
        }
        await #expect(throws: ServerEnvironmentError.invalidBaseURL) {
            _ = try await tokens.refreshToken(identityURL: identity, refreshToken: "fixture-refresh")
        }
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: ["{\"kdf\":0,\"kdfIterations\":-1}", "{\"kdf\":1,\"kdfMemory\":4294967296}",
                      "{\"kdf\":1,\"kdfParallelism\":0}", "{\"kdf\":2}"])
    func malformedPreloginParametersThrowTypedErrorWithoutTrapping(_ body: String) async {
        let http = AuthTransportHTTPStub()
        http.responses = [HTTPResponse(statusCode: 200, headers: [:], body: Foundation.Data(body.utf8))]
        await #expect(throws: AuthFlowError.invalidEncryptionParameters) {
            _ = try await DefaultPreloginService(httpClient: http).fetchKdf(
                email: "fixture@example.com",
                identityURL: URL(string: "https://vault.example.com/identity")!
            )
        }
        #expect(http.requests.count == 1)
    }

    @Test
    func omittedArgonFieldsResolveAtTheLiveDataPort() async throws {
        let http = AuthTransportHTTPStub()
        http.responses = [HTTPResponse(statusCode: 200, headers: [:], body: Foundation.Data(#"{"kdf":1}"#.utf8))]
        let parameters = try await DefaultPreloginService(httpClient: http).fetchKdf(
            email: "fixture@example.com",
            identityURL: URL(string: "https://vault.example.com/identity")!
        )
        #expect(parameters == .argon2id(iterations: 3, memory: 64, parallelism: 4))
    }

    @Test(arguments: [true, false])
    func cancelledConsumersCannotReceiveLateNoncooperativeTransportResults(prelogin: Bool) async {
        let http = PausedAuthTransport(response: HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Foundation.Data((prelogin ? #"{"kdf":0}"# :
                    #"{"access_token":"fixture-access","expires_in":3600,"token_type":"Bearer"}"#).utf8)
        ))
        let identity = URL(string: "https://vault.example.com/identity")!
        let caller = Task {
            if prelogin {
                _ = try await DefaultPreloginService(httpClient: http).fetchKdf(
                    email: "fixture@example.com",
                    identityURL: identity
                )
            } else {
                _ = try await DefaultIdentityTokenService(httpClient: http).requestToken(
                    identityURL: identity,
                    username: "fixture@example.com",
                    passwordHash: "fixture-hash",
                    device: device,
                    twoFactor: nil
                )
            }
        }
        await http.waitUntilEntered()
        caller.cancel()
        await http.release()
        await #expect(throws: CancellationError.self) { try await caller.value }
    }
}

private actor PausedAuthTransport: HTTPClient {
    private enum FixtureError: Error { case unsupportedTransfer }
    private let response: HTTPResponse
    private var continuation: CheckedContinuation<HTTPResponse, Never>?
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    init(response: HTTPResponse) { self.response = response }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() { continuation?.resume(returning: response); continuation = nil }
    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse { throw FixtureError.unsupportedTransfer }
    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse { throw FixtureError.unsupportedTransfer }
}
