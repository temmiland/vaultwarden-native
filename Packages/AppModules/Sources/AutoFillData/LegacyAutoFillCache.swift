import AutoFillContract
import BitwardenSDKAdapter
import Foundation

/// The encrypted cache format consumed by the existing AutoFill extension. Keep this wire model
/// in AutoFillData so app composition and the extension share the compatibility boundary without
/// making either consumer depend on a presentation target.
public struct SharedVaultCacheData: Codable, Sendable {
    public var ciphers: [CipherResponseDTO]
    public var organizationKeys: [String: String]
    public var updatedAt: Date
    /// Missing in legacy files. Such files cannot authorize a new extension invocation.
    public var owner: AutoFillAccountIdentity? = nil
    public var revision: UUID? = nil
    /// Repository projection order; UUID remains the extension's per-invocation version fence.
    public var projectionRevision: UInt64? = nil

    public init(
        ciphers: [CipherResponseDTO],
        organizationKeys: [String: String],
        updatedAt: Date,
        owner: AutoFillAccountIdentity? = nil,
        revision: UUID? = nil,
        projectionRevision: UInt64? = nil
    ) {
        self.ciphers = ciphers
        self.organizationKeys = organizationKeys
        self.updatedAt = updatedAt
        self.owner = owner
        self.revision = revision
        self.projectionRevision = projectionRevision
    }

    public func validate(for expectedOwner: AutoFillAccountIdentity) throws {
        guard owner == expectedOwner, revision != nil else { throw SharedVaultCacheError.wrongAccount }
    }
}

public enum SharedVaultCacheError: Error, Equatable, Sendable {
    case containerUnavailable
    case missingCache
    case wrongAccount
    case cacheTooLarge
}

/// Bridges the current encrypted projection contract to the existing extension cache wire format.
/// This adapter is intentionally narrow and does not expose SDK DTOs to feature presentation.
public struct LegacyAutoFillCacheCodec: AutoFillProjectionEncoding {
    private let owner: AutoFillAccountIdentity

    public init(owner: AutoFillAccountIdentity) {
        self.owner = owner
    }

    public func encode(_ envelope: AutoFillCacheEnvelope) throws -> Foundation.Data {
        guard envelope.accountID == owner.userID else { throw SharedVaultCacheError.wrongAccount }
        let ciphers = try envelope.encryptedLoginRecords.map {
            try JSONDecoder().decode(CipherResponseDTO.self, from: $0.encryptedCipherPayload)
        }
        let cache = SharedVaultCacheData(
            ciphers: ciphers,
            organizationKeys: envelope.encryptedOrganizationKeys,
            updatedAt: envelope.generatedAt,
            owner: owner,
            revision: UUID(),
            projectionRevision: envelope.revision
        )
        return try JSONEncoder().encode(cache)
    }

    public func decode(_ data: Foundation.Data) throws -> AutoFillCacheEnvelope {
        let cache = try JSONDecoder().decode(SharedVaultCacheData.self, from: data)
        try cache.validate(for: owner)
        return try AutoFillCacheEnvelope(
            accountID: owner.userID,
            revision: cache.projectionRevision ?? 0,
            generatedAt: cache.updatedAt,
            encryptedLoginRecords: try cache.ciphers.compactMap { cipher in
                guard let id = cipher.id, cipher.deletedDate == nil, cipher.archivedDate == nil else { return nil }
                return EncryptedLoginRecord(
                    id: id,
                    deletedAt: nil,
                    encryptedCipherPayload: try JSONEncoder().encode(cipher)
                )
            },
            encryptedOrganizationKeys: cache.organizationKeys
        )
    }
}
