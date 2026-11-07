import Domain
import Foundation
import Networking

/// Account-scoped settings data access. The session runtime owns token lookup, cancellation and
/// late-result rejection; SettingsPresentation sees only Domain device summaries.
public actor DefaultSettingsRepository: SettingsRepository {
    private let runtime: SessionRuntime
    private let http: any HTTPClient

    public init(runtime: SessionRuntime, http: any HTTPClient) {
        self.runtime = runtime
        self.http = http
    }

    public func fetchDevices() async throws -> [RegisteredDevice] {
        try await perform(path: "devices", method: .get) { response in
            let body: DeviceListResponse
            do { body = try FlexibleKeyDecoding.makeDecoder().decode(DeviceListResponse.self, from: response.body) }
            catch { throw SettingsRepositoryError.invalidResponse }
            return (body.data ?? []).compactMap { device in
                guard let id = device.id, Self.isSafeDeviceID(id) else { return nil }
                return RegisteredDevice(
                    id: id,
                    name: device.name ?? "Unknown device",
                    isTrusted: device.isTrusted ?? false,
                    lastActivityDate: device.lastActivityDate.flatMap(Self.parseDate)
                )
            }
        }
    }

    public func revokeDevice(id: String) async throws {
        guard Self.isSafeDeviceID(id) else { throw SettingsRepositoryError.invalidResponse }
        _ = try await perform(path: "devices/\(id)", method: .delete) { _ in () }
    }

    private func perform<Value: Sendable>(
        path: String,
        method: HTTPRequest.Method,
        decode: @escaping @Sendable (HTTPResponse) throws -> Value
    ) async throws -> Value {
        let runtime = runtime
        let http = http
        return try await runtime.perform {
            let token = try await runtime.requireAccessToken()
            let url = runtime.account.environment.apiURL.appendingPathComponent(path)
            let request = HTTPRequest(
                url: url,
                method: method,
                headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"],
                redirectPolicy: .reject
            )
            let response = try await http.send(request)
            try runtime.checkAccess()
            guard response.isSuccess else { throw SettingsRepositoryError.server(statusCode: response.statusCode) }
            return try decode(response)
        }
    }

    private static func isSafeDeviceID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (0x30 ... 0x39).contains($0) || (0x41 ... 0x5A).contains($0)
                || (0x61 ... 0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

private struct DeviceListResponse: Decodable {
    let data: [DeviceResponse]?
}

private struct DeviceResponse: Decodable {
    let id: String?
    let name: String?
    let isTrusted: Bool?
    let lastActivityDate: String?
}
