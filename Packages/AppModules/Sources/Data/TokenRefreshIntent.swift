import Foundation
import SecurityStorage

/// No tokens, keys, response bodies or account display metadata are persisted here. A request
/// may have consumed a rotating token even if its response was lost. Never infer non-execution
/// from a process restart, timeout, cancellation or a malformed successful response.
public struct TokenRefreshIntent: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    static let key = "auth.refresh.intent.v1"
    let schemaVersion: Int
    public let id: UUID
    public let scope: TokenScope
    public let generation: UInt64
    public let publicationEpoch: UUID

    public init(scope: TokenScope, generation: UInt64, publicationEpoch: UUID) {
        schemaVersion = 1
        id = UUID()
        self.scope = scope
        self.generation = generation
        self.publicationEpoch = publicationEpoch
    }

    static func read(from keychain: any KeychainStoring) throws -> Self? {
        let data: Foundation.Data
        do { data = try keychain.read(key) }
        catch KeychainStoreError.notFound { return nil }
        guard let intent = try? JSONDecoder().decode(Self.self, from: data),
              intent.schemaVersion == 1, intent.generation > 0 else { throw KeychainStoreError.decodeFailed }
        return intent
    }

    public var description: String { "TokenRefreshIntent(<redacted>)" }
    public var debugDescription: String { description }
}

public enum TokenRefreshRecoveryError: Error, Sendable, Equatable {
    /// Preserve the current session; require a fresh sign-in before another rotating request.
    /// This is NOT evidence of invalid_grant, and must not cause automatic logout.
    case unconfirmedRotation
}
