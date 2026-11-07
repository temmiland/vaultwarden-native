import Foundation

/// Public KDF values at credential ports, independent of the crypto SDK and wire field names.
/// SDK adapters validate even explicitly constructed values before invoking cryptography.
public enum KeyDerivationParameters: Sendable, Equatable {
    case pbkdf2(iterations: UInt32)
    case argon2id(iterations: UInt32, memory: UInt32, parallelism: UInt32)
}

public protocol PreloginService: Sendable {
    func fetchKdf(email: String, identityURL: URL) async throws -> KeyDerivationParameters
}

/// Stable presentation errors; no raw HTTP/SDK diagnostics or credential values are retained.
public enum AuthFlowError: Error, LocalizedError, Equatable, Sendable {
    case missingCryptoState
    case invalidAccessToken
    case invalidEncryptionParameters

    public var errorDescription: String? {
        switch self {
        case .missingCryptoState:
            "This account doesn't support master-password unlock, which is all this app currently handles."
        case .invalidAccessToken:
            "The server's response couldn't be understood."
        case .invalidEncryptionParameters:
            "The account's encryption settings are unsupported or invalid. Sign in again or check the server configuration."
        }
    }
}
