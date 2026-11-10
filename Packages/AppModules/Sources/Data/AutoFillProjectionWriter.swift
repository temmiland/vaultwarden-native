import AutoFillContract
import Foundation

/// Whether the AutoFill projection represents the current vault revision. A projection failure
/// never rolls back a server mutation, but it is never reported as silently current either.
public enum AutoFillProjectionHealth: Sendable, Equatable {
    case current(revision: UInt64)
    case stale(lastSuccessfulRevision: UInt64)
    case unavailable
}

/// Storage boundary for the encrypted-only App Group projection. Its narrow surface is deliberate:
/// the writer controls filenames, revision ordering, account validation and atomic replacement;
/// callers never construct paths or write cache bytes themselves.
public protocol AutoFillProjectionFileStore: Sendable {
    func readProjection() throws -> Foundation.Data?
    func replaceProjectionAtomically(with data: Foundation.Data) throws
    func removeProjection() throws
}

public struct JSONAutoFillProjectionEncoding: AutoFillProjectionEncoding {
    public init() {}

    public func encode(_ envelope: AutoFillCacheEnvelope) throws -> Foundation.Data {
        try JSONEncoder().encode(envelope)
    }

    public func decode(_ data: Foundation.Data) throws -> AutoFillCacheEnvelope {
        try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: data).validated()
    }
}

/// Owns an account-bound, revisioned encrypted AutoFill cache. It contains no plaintext fields:
/// input records are already encrypted SDK payloads and deleted records are excluded before
/// encoding. The actor serializes all writes so an older sync cannot overwrite a newer mutation.
public actor AutoFillProjectionWriter {
    private let accountID: String
    private let fileStore: AutoFillProjectionFileStore
    private let encoding: AutoFillProjectionEncoding
    private let now: @Sendable () -> Date
    private var isInitialized = false
    private var lastSuccessfulRevision: UInt64?
    private var health: AutoFillProjectionHealth = .unavailable

    public init(
        accountID: String,
        fileStore: AutoFillProjectionFileStore,
        encoding: AutoFillProjectionEncoding = JSONAutoFillProjectionEncoding(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountID = accountID
        self.fileStore = fileStore
        self.encoding = encoding
        self.now = now
    }

    public func currentHealth() -> AutoFillProjectionHealth {
        health
    }

    /// Writes a projection for one committed vault revision. The caller supplies only encrypted
    /// login records and encrypted organization keys; any deleted record is removed here as a
    /// second, non-bypassable safety boundary.
    @discardableResult
    public func project(
        revision: UInt64,
        encryptedLoginRecords: [EncryptedLoginRecord],
        encryptedOrganizationKeys: [String: String]
    ) -> AutoFillProjectionHealth {
        do {
            try initializeFromExistingProjectionIfNeeded()
            let projectionIsCurrent: Bool
            if case .current = health {
                projectionIsCurrent = true
            } else {
                projectionIsCurrent = false
            }
            if let lastSuccessfulRevision,
               revision < lastSuccessfulRevision || (revision == lastSuccessfulRevision && projectionIsCurrent) {
                return health
            }

            let envelope = try AutoFillCacheEnvelope(
                accountID: accountID,
                revision: revision,
                generatedAt: now(),
                encryptedLoginRecords: encryptedLoginRecords.filter { $0.deletedAt == nil },
                encryptedOrganizationKeys: encryptedOrganizationKeys
            )
            try fileStore.replaceProjectionAtomically(with: encoding.encode(envelope))
            lastSuccessfulRevision = revision
            health = .current(revision: revision)
            AutoFillDiagnostics.record(.cache)
        } catch {
            AutoFillDiagnostics.record(.cache, error: error)
            health = lastSuccessfulRevision.map(AutoFillProjectionHealth.stale(lastSuccessfulRevision:)) ?? .unavailable
        }
        return health
    }

    /// Used on lock/logout or when an unsafe legacy projection cannot be repaired. Removing the
    /// file is intentionally fail-closed: the extension shows no cache-backed credential rather
    /// than an entry whose account/revision is unknown.
    public func invalidate() {
        do {
            try fileStore.removeProjection()
            lastSuccessfulRevision = nil
            health = .unavailable
        } catch {
            // A failed removal leaves the last known status visible to the repository, which can
            // surface a repair warning. It must not claim that the cache is gone.
            health = lastSuccessfulRevision.map(AutoFillProjectionHealth.stale(lastSuccessfulRevision:)) ?? .unavailable
        }
    }

    private func initializeFromExistingProjectionIfNeeded() throws {
        guard !isInitialized else { return }
        guard let rawProjection = try fileStore.readProjection() else {
            isInitialized = true
            return
        }

        let existing: AutoFillCacheEnvelope
        do {
            existing = try encoding.decode(rawProjection)
        } catch {
            // A corrupt or obsolete-schema cache cannot be safely served during
            // the next session. Clear it before the first replacement attempt.
            try fileStore.removeProjection()
            lastSuccessfulRevision = nil
            health = .unavailable
            isInitialized = true
            return
        }

        guard existing.accountID == accountID else {
            try fileStore.removeProjection()
            isInitialized = true
            return
        }

        lastSuccessfulRevision = existing.revision
        health = .current(revision: existing.revision)
        isInitialized = true
    }
}

/// File-system implementation used by an app composition root after it resolves its App Group
/// directory. The temporary file lives beside the final file, so `moveItem`/`replaceItemAt` never
/// crosses a volume and remains atomic from the extension's reader's point of view.
public struct AtomicAutoFillProjectionFileStore: AutoFillProjectionFileStore, @unchecked Sendable {
    private let directoryURL: URL
    private let finalURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL,
        fileName: String = "autofill-cache-v1.json",
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        finalURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        self.fileManager = fileManager
    }

    public func readProjection() throws -> Foundation.Data? {
        guard fileManager.fileExists(atPath: finalURL.path) else { return nil }
        return try Foundation.Data(contentsOf: finalURL)
    }

    public func replaceProjectionAtomically(with data: Foundation.Data) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: directoryURL.path)

        let temporaryURL = directoryURL.appendingPathComponent(".autofill-projection-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: 0o600)]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try data.write(to: temporaryURL, options: [.completeFileProtection])
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: temporaryURL.path)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        try handle.synchronize()
        try handle.close()

        if fileManager.fileExists(atPath: finalURL.path) {
            _ = try fileManager.replaceItemAt(finalURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: finalURL.path)
    }

    public func removeProjection() throws {
        guard fileManager.fileExists(atPath: finalURL.path) else { return }
        try fileManager.removeItem(at: finalURL)
    }
}
