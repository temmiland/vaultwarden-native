import Foundation
import SecurityStorage

public enum AuthCleanupRecoveryError: Error, Sendable, Equatable { case pending }

/// Durable, nonsecret deny marker shared by app and extension. Access only while holding the
/// existing shared-token transaction lock. Logout wins over lock; never reset corrupt data.
struct AuthCleanupIntent: Codable, Equatable {
    enum Kind: String, Codable { case lock, logout }
    static let key = "auth.cleanup.v1"
    let schemaVersion: Int
    let kind: Kind
    init(_ kind: Kind) { schemaVersion = 1; self.kind = kind }

    static func read(from keychain: any KeychainStoring) throws -> AuthCleanupIntent? {
        let data: Foundation.Data
        do { data = try keychain.read(key) }
        catch KeychainStoreError.notFound { return nil }
        guard let value = try? JSONDecoder().decode(Self.self, from: data), value.schemaVersion == 1 else {
            throw KeychainStoreError.decodeFailed
        }
        return value
    }

    static func requireNone(in keychain: any KeychainStoring) throws {
        guard try read(from: keychain) == nil else { throw AuthCleanupRecoveryError.pending }
    }
}
