import AutoFillContract
import BitwardenSDKAdapter
import Foundation

/// A transient fence for exactly one encrypted registration projection. No secret material or
/// identity metadata is included in diagnostics; callers cannot invent a receipt.
public struct AutoFillCacheCommitReceipt: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let revision: UUID
    public let projectionRevision: UInt64?
    fileprivate let cipherID: String
    fileprivate let encryptedCipher: Foundation.Data
    fileprivate let proof: ExtensionUnlockProof
    public var description: String { "AutoFillCacheCommitReceipt(<redacted>)" }
    public var debugDescription: String { description }
}

/// Encrypted-only cache access for the existing extension format. App Group resolution and
/// Keychain authorization are injected by composition; there is no dependency on a feature or
/// on app configuration. Atomic replacement keeps readers on a complete cache.
public struct LegacyAutoFillCacheStore: Sendable {
    public static let maximumCacheBytes = 64 * 1024 * 1024
    private let directoryURL: URL?
    private let authorization: any AutoFillCacheMutationAuthorizing
    private let readLimit: Int

    public init(
        directoryURL: URL?,
        authorization: any AutoFillCacheMutationAuthorizing,
        maximumCacheBytes: Int = LegacyAutoFillCacheStore.maximumCacheBytes
    ) {
        precondition(maximumCacheBytes >= 0 && maximumCacheBytes < Int.max)
        self.directoryURL = directoryURL
        self.authorization = authorization
        readLimit = maximumCacheBytes
    }

    public func read() throws -> SharedVaultCacheData? {
        guard let directoryURL else { return nil }
        let url = directoryURL.appendingPathComponent("autofill-cache.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Foundation.Data()
        while true {
            let remaining = readLimit - data.count
            let chunkSize = min(1_048_576, remaining + 1)
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            guard chunk.count <= remaining else { throw SharedVaultCacheError.cacheTooLarge }
            data.append(chunk)
        }
        return try JSONDecoder().decode(SharedVaultCacheData.self, from: data)
    }

    /// Never invent a cache after a confirmed server write. The exact unlock and cache revisions
    /// are checked inside the shared critical section, so stale invocations cannot publish over
    /// a new app sync, unlock or another extension mutation.
    public func upsert(
        _ cipher: CipherResponseDTO,
        for owner: AutoFillAccountIdentity,
        requiringProof proof: ExtensionUnlockProof,
        cacheRevision: UUID
    ) throws {
        _ = try upsertReturningReceipt(cipher, for: owner, requiringProof: proof, cacheRevision: cacheRevision)
    }

    public func upsertReturningReceipt(
        _ cipher: CipherResponseDTO,
        for owner: AutoFillAccountIdentity,
        requiringProof proof: ExtensionUnlockProof,
        cacheRevision: UUID
    ) throws -> AutoFillCacheCommitReceipt {
        guard let directoryURL else { throw SharedVaultCacheError.containerUnavailable }
        guard proof.account == owner else { throw SharedVaultCacheError.wrongAccount }
        guard let id = cipher.id, !id.isEmpty, SDKVaultAccessPolicy.isEligibleForAutoFill(cipher) else {
            throw AutoFillOperationError.accessDenied
        }
        return try authorization.withAuthorizedCacheMutation(requiring: proof) {
            guard let cache = try read() else { throw SharedVaultCacheError.missingCache }
            try cache.validate(for: owner)
            guard cache.revision == cacheRevision, cache.projectionRevision != .max else { throw CancellationError() }
            let updated = Self.upserting(cipher, into: cache)
            guard let updatedRevision = updated.revision else { throw CancellationError() }
            let encryptedCipher = try Self.encodeCipher(cipher)
            let encoded = try JSONEncoder().encode(updated)
            let url = directoryURL.appendingPathComponent("autofill-cache.json")
            #if os(iOS)
                try encoded.write(to: url, options: [.atomic, .completeFileProtection])
            #else
                try encoded.write(to: url, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
            return AutoFillCacheCommitReceipt(
                revision: updatedRevision,
                projectionRevision: updated.projectionRevision,
                cipherID: id,
                encryptedCipher: encryptedCipher,
                proof: proof
            )
        }
    }

    /// Recheck under the same shared authorization lock around every asynchronous identity step.
    /// A legacy cache without a monotonic fence can be repaired by full app sync, not guessed here.
    public func requireCurrent(_ receipt: AutoFillCacheCommitReceipt, requiring proof: ExtensionUnlockProof) throws {
        guard receipt.proof == proof else { throw CancellationError() }
        try authorization.withAuthorizedCacheMutation(requiring: proof) {
            guard let cache = try read() else { throw SharedVaultCacheError.missingCache }
            try cache.validate(for: proof.account)
            guard receipt.projectionRevision != nil, cache.revision == receipt.revision,
                  cache.projectionRevision == receipt.projectionRevision else { throw CancellationError() }
            let matches = cache.ciphers.filter { $0.id == receipt.cipherID }
            guard matches.count == 1, let cipher = matches.first, SDKVaultAccessPolicy.isEligibleForAutoFill(cipher),
                  try Self.encodeCipher(cipher) == receipt.encryptedCipher else { throw CancellationError() }
        }
    }

    private static func encodeCipher(_ cipher: CipherResponseDTO) throws -> Foundation.Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(cipher)
    }

    public static func loginCiphers(from ciphers: [CipherResponseDTO]) -> [CipherResponseDTO] {
        ciphers.filter(SDKVaultAccessPolicy.isEligibleForAutoFill)
    }

    public static func upserting(_ cipher: CipherResponseDTO, into cache: SharedVaultCacheData) -> SharedVaultCacheData {
        guard let id = cipher.id, !id.isEmpty else { return cache }
        var ciphers = loginCiphers(from: cache.ciphers.filter { $0.id != id })
        if SDKVaultAccessPolicy.isEligibleForAutoFill(cipher) { ciphers.append(cipher) }
        return SharedVaultCacheData(
            ciphers: ciphers,
            organizationKeys: cache.organizationKeys,
            updatedAt: Date(),
            owner: cache.owner,
            revision: UUID(),
            projectionRevision: cache.projectionRevision.map { $0 == .max ? .max : $0 + 1 }
        )
    }
}
