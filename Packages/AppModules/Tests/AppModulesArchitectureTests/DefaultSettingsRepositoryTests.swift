import Data
import Domain
import Foundation
import Networking
import Testing

@Suite
struct DefaultSettingsRepositoryTests {
    @Test
    func fetchDevicesUsesScopedBearerAndRejectsRedirects() async throws {
        let runtime = try makeRuntime()
        let http = SettingsHTTPFixture(
            status: 200,
            body: #"{"data":[{"id":"device-1","name":"MacBook","isTrusted":true,"lastActivityDate":"2026-09-26T12:30:00Z"}]}"#
        )
        let repository = DefaultSettingsRepository(runtime: runtime, http: http)

        let devices = try await repository.fetchDevices()

        #expect(devices.count == 1)
        #expect(devices.first?.id == "device-1")
        #expect(devices.first?.name == "MacBook")
        #expect(devices.first?.isTrusted == true)
        let request = try #require(await http.lastRequest)
        #expect(request.url == URL(string: "https://vault.example.com/vault/api/devices")!)
        #expect(request.method == .get)
        #expect(request.headers["Authorization"] == "Bearer fake-test-token")
        #expect(request.redirectPolicy == .reject)
    }

    @Test
    func revokeUsesDeleteForOneValidatedDevice() async throws {
        let http = SettingsHTTPFixture(status: 200, body: "{}")
        let repository = DefaultSettingsRepository(runtime: try makeRuntime(), http: http)

        try await repository.revokeDevice(id: "device_42")

        let request = try #require(await http.lastRequest)
        #expect(request.url == URL(string: "https://vault.example.com/vault/api/devices/device_42")!)
        #expect(request.method == .delete)
        #expect(request.redirectPolicy == .reject)
    }

    @Test
    func unsafeDeviceIdentifiersAreRejectedBeforeTransport() async throws {
        let http = SettingsHTTPFixture(status: 200, body: "{}")
        let repository = DefaultSettingsRepository(runtime: try makeRuntime(), http: http)

        await #expect(throws: SettingsRepositoryError.invalidResponse) {
            try await repository.revokeDevice(id: "../fake")
        }
        #expect(await http.lastRequest == nil)
    }

    @Test
    func serverErrorsRemainTypedAndDoNotRetainResponseBody() async throws {
        let http = SettingsHTTPFixture(status: 500, body: #"{"error":"fake-private-response"}"#)
        let repository = DefaultSettingsRepository(runtime: try makeRuntime(), http: http)

        await #expect(throws: SettingsRepositoryError.server(statusCode: 500)) {
            try await repository.fetchDevices()
        }
        #expect(!String(reflecting: SettingsRepositoryError.server(statusCode: 500)).contains("fake-private-response"))
    }

    @Test
    func revokedRuntimeCannotStartAnotherSettingsRequest() async throws {
        let resource = SettingsRuntimeResource()
        let runtime = try makeRuntime(resource: resource)
        let http = SettingsHTTPFixture(status: 200, body: #"{"data":[]}"#)
        let repository = DefaultSettingsRepository(runtime: runtime, http: http)
        await runtime.revoke(.lock)

        await #expect(throws: CancellationError.self) { try await repository.fetchDevices() }
        #expect(await http.lastRequest == nil)
    }

    private func makeRuntime(resource: SettingsRuntimeResource? = nil) throws -> SessionRuntime {
        let account = AccountSession(
            accountID: AccountID(rawValue: "test-account"),
            email: "test@example.com",
            environment: try ServerEnvironment(baseURL: URL(string: "https://vault.example.com/vault/")!)
        )
        return SessionRuntime(
            account: account,
            resource: resource ?? SettingsRuntimeResource(),
            tokens: SettingsRuntimeTokens()
        )
    }
}

private actor SettingsHTTPFixture: HTTPClient {
    private let response: HTTPResponse
    private(set) var lastRequest: HTTPRequest?

    init(status: Int, body: String) {
        response = HTTPResponse(statusCode: status, headers: [:], body: Foundation.Data(body.utf8))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lastRequest = request
        return response
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        throw CancellationError()
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        throw CancellationError()
    }
}

private final class SettingsRuntimeResource: SessionResource, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool { lock.withLock { active } }

    func revoke() { lock.withLock { active = false } }
}

private actor SettingsRuntimeTokens: SessionTokenProviding {
    func getAccessToken() async -> String? { "fake-test-token" }
    func revoke() async {}
}
