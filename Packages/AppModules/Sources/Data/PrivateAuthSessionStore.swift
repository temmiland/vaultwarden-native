import Foundation
import SecurityStorage

public struct PersistedAuthSession: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let schemaVersion: Int
    public let account: StoredAuthAccount
    public let scope: TokenScope
    public let tokens: TokenPair

    public init(account: StoredAuthAccount, scope: TokenScope, tokens: TokenPair) {
        schemaVersion = 1
        self.account = account
        self.scope = scope
        self.tokens = tokens
    }

    public var description: String { "PersistedAuthSession(<redacted>)" }
    public var debugDescription: String { description }
}

/// ONE replace-in-place Keychain value is the durable authority for account + tokens. A failed
/// login write leaves the previous record intact. No inference from separately stored legacy
/// account/token records, JWT decoding, timestamps or shared generations is permitted.
/// Callers serialize compound app/shared transitions through the cross-process token lock.
public struct PrivateAuthSessionStore: Sendable {
    public static let key = "auth.session.v1"
    private let keychain: any KeychainStoring

    public init(keychain: any KeychainStoring) { self.keychain = keychain }

    public func load() throws -> PersistedAuthSession? {
        let data: Foundation.Data
        do { data = try keychain.read(Self.key) }
        catch KeychainStoreError.notFound { return nil }
        let record: PersistedAuthSession
        do { record = try JSONDecoder().decode(PersistedAuthSession.self, from: data) }
        catch { throw KeychainStoreError.decodeFailed }
        try validate(record)
        return record
    }

    public func save(_ record: PersistedAuthSession) throws {
        try validate(record)
        try keychain.write(JSONEncoder().encode(record), for: Self.key)
    }

    public func clear() throws { try keychain.remove(Self.key) }

    /// Pure candidate validation. Compound transitions validate before revoking an old grant or
    /// publishing to either store; this method does not read or mutate Keychain.
    public func validate(_ record: PersistedAuthSession) throws {
        guard record.schemaVersion == 1, record.scope.account == record.account.tokenIdentity,
              !record.account.userId.isEmpty, !record.tokens.accessToken.isEmpty,
              !record.tokens.refreshToken.isEmpty, record.tokens.generation > 0,
              record.tokens.expiresAt.timeIntervalSinceReferenceDate.isFinite,
              record.tokens.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              let scheme = record.account.serverBaseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme), record.account.serverBaseURL.host != nil
        else { throw KeychainStoreError.decodeFailed }
    }
}
