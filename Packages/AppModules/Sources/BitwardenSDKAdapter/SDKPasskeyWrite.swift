import BitwardenSdk
import Domain
import Foundation
import Networking

/// No raw transport/SDK diagnostics escape the registration commit boundary.
public enum SDKPasskeyWriteError: Error, Sendable, Equatable {
    case notSubmitted, rejected, outcomeUnknown, confirmedButUnreadable
}

extension SDKCipherService {
    public func savePasskeyResponse(_ cipher: SDKAutoFillEncryptedCipher) async throws -> CipherResponseDTO {
        guard cipher.encryptedFor == userID else { throw SDKPasskeyWriteError.notSubmitted }
        return try await savePasskeyResponse(cipher.value)
    }

    /// Used only by existing passkey registration. Distinguishes a pre-submit failure, a definite
    /// rejection, an ambiguous request and a successful status with unusable projection payload.
    public func savePasskeyResponse(_ cipher: Cipher) async throws -> CipherResponseDTO {
        let body: Data
        do {
            body = try JSONEncoder().encode(CipherRequestDTO(
                cipher: cipher,
                encryptedFor: userID,
                lastKnownRevisionDate: cipher.id == nil ? nil : cipher.revisionDate
            ))
        } catch { throw SDKPasskeyWriteError.notSubmitted }
        let token: String
        do { token = try await authorizedToken() }
        catch let error as SessionAuthorizationError { throw error } // classified before cipher HTTP
        catch { throw SDKPasskeyWriteError.notSubmitted }
        let url = cipher.id.map { apiURL.appendingPathComponent("ciphers").appendingPathComponent($0) }
            ?? apiURL.appendingPathComponent("ciphers")
        let response: HTTPResponse
        do {
            response = try await httpClient.send(HTTPRequest(
                url: url,
                method: cipher.id == nil ? .post : .put,
                headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"],
                body: body,
                redirectPolicy: .reject
            ))
        } catch { throw SDKPasskeyWriteError.outcomeUnknown }
        guard response.isSuccess else {
            // Timeouts/conflicts/5xx need inspection, not a promise that nothing was committed.
            if [400, 401, 403, 404, 405, 413, 422, 429].contains(response.statusCode) { throw SDKPasskeyWriteError.rejected }
            throw SDKPasskeyWriteError.outcomeUnknown
        }
        do {
            var persisted = try JSONDecoder().decode(CipherResponseDTO.self, from: response.body)
            persisted.id = persisted.id ?? cipher.id // preserve the existing omitted-update-ID behavior
            guard let id = persisted.id, !id.isEmpty, cipher.id == nil || cipher.id == id,
                  persisted.encryptedFor == nil || persisted.encryptedFor == userID,
                  SDKVaultAccessPolicy.isEligibleForAutoFill(persisted) else { throw SDKPasskeyWriteError.confirmedButUnreadable }
            return persisted
        } catch { throw SDKPasskeyWriteError.confirmedButUnreadable }
    }
}
