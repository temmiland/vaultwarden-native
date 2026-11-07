import BitwardenSdk
import Foundation
import Networking

/// Pushes already-encrypted SDK ciphers to the configured API. Encryption and session authority
/// remain with the caller; this boundary contains only SDK/wire mapping and HTTP requests.
public protocol SDKCipherServicing: Sendable {
    /// Fetches a single cipher's current (still-encrypted) server state - used to refresh a cipher
    /// after an out-of-band change the create/update endpoints don't return, like an attachment
    /// upload or delete.
    func get(id: String) async throws -> Cipher
    func create(_ cipher: Cipher) async throws -> Cipher
    func update(id: String, _ cipher: Cipher) async throws -> Cipher
    func delete(id: String) async throws
}

public enum SDKCipherServiceError: Error, Sendable, Equatable {
    case missingAccessToken
}

public struct SDKCipherService: SDKCipherServicing, Sendable {
    let httpClient: any HTTPClient
    let apiURL: URL
    let userID: String
    let accessToken: @Sendable () async -> String?
    let requireAccessToken: (@Sendable () async throws -> String)?

    public init(
        httpClient: any HTTPClient,
        apiURL: URL,
        userID: String,
        accessToken: @escaping @Sendable () async -> String?,
        requireAccessToken: (@Sendable () async throws -> String)? = nil
    ) {
        self.httpClient = httpClient
        self.apiURL = apiURL
        self.userID = userID
        self.accessToken = accessToken
        self.requireAccessToken = requireAccessToken
    }

    public func get(id: String) async throws -> Cipher {
        let url = apiURL.appendingPathComponent("ciphers").appendingPathComponent(id)
        let response = try await send(url: url, method: .get, body: nil)
        return try JSONDecoder().decode(CipherResponseDTO.self, from: response.body).toSDKCipher()
    }

    public func create(_ cipher: Cipher) async throws -> Cipher {
        try await createResponse(cipher).toSDKCipher()
    }

    /// Raw server response for a create. The AutoFill extension uses this narrow API to project a
    /// server-confirmed passkey write into its encrypted offline cache without reconstructing a
    /// lossy DTO from an SDK model.
    public func createResponse(_ cipher: Cipher) async throws -> CipherResponseDTO {
        let url = apiURL.appendingPathComponent("ciphers")
        let body = try JSONEncoder().encode(CipherRequestDTO(cipher: cipher, encryptedFor: userID))
        let response = try await send(url: url, method: .post, body: body)
        return try decodeWriteResponse(response.body)
    }

    public func update(id: String, _ cipher: Cipher) async throws -> Cipher {
        try await updateResponse(id: id, cipher).toSDKCipher()
    }

    /// Raw server response for an update; see `createResponse(_:)`.
    public func updateResponse(id: String, _ cipher: Cipher) async throws -> CipherResponseDTO {
        let url = apiURL.appendingPathComponent("ciphers").appendingPathComponent(id)
        let body = try JSONEncoder().encode(CipherRequestDTO(
            cipher: cipher, encryptedFor: userID, lastKnownRevisionDate: cipher.revisionDate
        ))
        let response = try await send(url: url, method: .put, body: body)
        return try decodeWriteResponse(response.body)
    }

    public func delete(id: String) async throws {
        let url = apiURL.appendingPathComponent("ciphers").appendingPathComponent(id)
        _ = try await send(url: url, method: .delete, body: nil)
    }

    private func send(url: URL, method: HTTPRequest.Method, body: Data?) async throws -> HTTPResponse {
        let token = try await authorizedToken()
        var headers = ["Authorization": "Bearer \(token)"]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        let request = HTTPRequest(url: url, method: method, headers: headers, body: body, redirectPolicy: .reject)
        let response = try await httpClient.send(request)
        guard response.isSuccess else { throw HTTPStatusError(response: response) }
        return response
    }

    private func decodeWriteResponse(_ data: Data) throws -> CipherResponseDTO {
        let response = try JSONDecoder().decode(CipherResponseDTO.self, from: data)
        guard response.encryptedFor == nil || response.encryptedFor == userID else {
            throw CipherMappingError.invalidField("encryptedFor")
        }
        return response
    }

    func authorizedToken() async throws -> String {
        try Task.checkCancellation()
        let token: String
        if let requireAccessToken { token = try await requireAccessToken() }
        else {
            guard let available = await accessToken() else { throw SDKCipherServiceError.missingAccessToken }
            token = available
        }
        try Task.checkCancellation()
        return token
    }
}
