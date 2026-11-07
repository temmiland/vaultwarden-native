import Foundation

/// Persistence-only ownership metadata. A user ID alone is not unique across servers.
public struct TokenAccountIdentity: Codable, Sendable, Equatable {
    public let userID: String
    public let serverBaseURL: URL

    public init(userID: String, serverBaseURL: URL) {
        self.userID = userID
        self.serverBaseURL = serverBaseURL
    }
}

/// A new password/2FA sign-in starts a new lineage, even for the same account. Lock/unlock and
/// token rotation keep this lineage; generations are comparable ONLY inside the same scope.
public struct TokenScope: Codable, Sendable, Equatable {
    public let account: TokenAccountIdentity
    public let authenticationID: UUID

    public init(account: TokenAccountIdentity, authenticationID: UUID = UUID()) {
        self.account = account
        self.authenticationID = authenticationID
    }
}

public struct TokenPair: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let generation: UInt64
    public let updatedAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        generation: UInt64 = 1,
        updatedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.generation = generation
        self.updatedAt = updatedAt
    }

    /// Legacy payloads may be inspected, but are never imported as an authenticated session.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try values.decode(String.self, forKey: .accessToken)
        refreshToken = try values.decode(String.self, forKey: .refreshToken)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        generation = try values.decodeIfPresent(UInt64.self, forKey: .generation) ?? 0
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? expiresAt
    }

    public func versioned(generation: UInt64, updatedAt: Date = Date()) -> TokenPair {
        TokenPair(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            generation: generation,
            updatedAt: updatedAt
        )
    }

    public var isExpired: Bool { isExpired(at: Date()) }
    public func isExpired(at date: Date) -> Bool { date >= expiresAt.addingTimeInterval(-30) }
    public var description: String { "TokenPair(<redacted>)" }
    public var debugDescription: String { description }
}

/// Wrapped keys are still sensitive. This record belongs to persistence, not Domain/UI session
/// state; credential orchestration consumes it inside Data, not directly in presentation.
public struct StoredAuthAccount: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let userId: String
    public let email: String
    public let serverBaseURL: URL
    public let kdfType: Int?
    public let kdfIterations: Int?
    public let kdfMemory: Int?
    public let kdfParallelism: Int?
    public let encryptedUserKey: String
    public let encryptedPrivateKey: String
    public var isBiometricUnlockEnabled: Bool
    public var isPinUnlockEnabled: Bool

    public init(
        userId: String,
        email: String,
        serverBaseURL: URL,
        kdfType: Int?,
        kdfIterations: Int?,
        kdfMemory: Int?,
        kdfParallelism: Int?,
        encryptedUserKey: String,
        encryptedPrivateKey: String,
        isBiometricUnlockEnabled: Bool,
        isPinUnlockEnabled: Bool = false
    ) {
        self.userId = userId
        self.email = email
        self.serverBaseURL = serverBaseURL
        self.kdfType = kdfType
        self.kdfIterations = kdfIterations
        self.kdfMemory = kdfMemory
        self.kdfParallelism = kdfParallelism
        self.encryptedUserKey = encryptedUserKey
        self.encryptedPrivateKey = encryptedPrivateKey
        self.isBiometricUnlockEnabled = isBiometricUnlockEnabled
        self.isPinUnlockEnabled = isPinUnlockEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userId = try values.decode(String.self, forKey: .userId)
        email = try values.decode(String.self, forKey: .email)
        serverBaseURL = try values.decode(URL.self, forKey: .serverBaseURL)
        kdfType = try values.decodeIfPresent(Int.self, forKey: .kdfType)
        kdfIterations = try values.decodeIfPresent(Int.self, forKey: .kdfIterations)
        kdfMemory = try values.decodeIfPresent(Int.self, forKey: .kdfMemory)
        kdfParallelism = try values.decodeIfPresent(Int.self, forKey: .kdfParallelism)
        encryptedUserKey = try values.decode(String.self, forKey: .encryptedUserKey)
        encryptedPrivateKey = try values.decode(String.self, forKey: .encryptedPrivateKey)
        isBiometricUnlockEnabled = try values.decode(Bool.self, forKey: .isBiometricUnlockEnabled)
        isPinUnlockEnabled = try values.decodeIfPresent(Bool.self, forKey: .isPinUnlockEnabled) ?? false
    }

    public var tokenIdentity: TokenAccountIdentity {
        TokenAccountIdentity(userID: userId, serverBaseURL: serverBaseURL)
    }

    public var description: String { "StoredAuthAccount(<redacted>)" }
    public var debugDescription: String { description }
}
