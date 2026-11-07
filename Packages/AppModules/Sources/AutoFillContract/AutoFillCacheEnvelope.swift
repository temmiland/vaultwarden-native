import Foundation

/// Versioned, encrypted-only hand-off between the app and the AutoFill extension. Plaintext
/// passwords, TOTP seeds and private passkey material are intentionally not representable here.
public struct AutoFillCacheEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let oldestSupportedSchemaVersion = 1

    public let schemaVersion: Int
    public let accountID: String
    public let revision: UInt64
    public let generatedAt: Date
    public let encryptedLoginRecords: [EncryptedLoginRecord]
    public let encryptedOrganizationKeys: [String: String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        accountID: String,
        revision: UInt64,
        generatedAt: Date,
        encryptedLoginRecords: [EncryptedLoginRecord],
        encryptedOrganizationKeys: [String: String]
    ) throws {
        guard (Self.oldestSupportedSchemaVersion ... Self.currentSchemaVersion).contains(schemaVersion) else {
            throw AutoFillCacheContractError.unsupportedSchema(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        self.accountID = accountID
        self.revision = revision
        self.generatedAt = generatedAt
        self.encryptedLoginRecords = encryptedLoginRecords
        self.encryptedOrganizationKeys = encryptedOrganizationKeys
    }

    public func validated() throws -> Self {
        guard (Self.oldestSupportedSchemaVersion ... Self.currentSchemaVersion).contains(schemaVersion) else {
            throw AutoFillCacheContractError.unsupportedSchema(schemaVersion)
        }
        return self
    }
}

public struct EncryptedLoginRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let deletedAt: Date?
    public let encryptedCipherPayload: Data

    public init(id: String, deletedAt: Date?, encryptedCipherPayload: Data) {
        self.id = id
        self.deletedAt = deletedAt
        self.encryptedCipherPayload = encryptedCipherPayload
    }
}

public enum AutoFillCacheContractError: Error, Sendable, Equatable {
    case unsupportedSchema(Int)
}
