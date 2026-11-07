import Foundation

public enum SensitiveTemporaryFileStoreError: Error, Sendable, Equatable {
    case invalidWorkDirectory
    case sessionInactive
    case unsafeRoot
    case cleanupFailed
    case couldNotCreateFile
}

/// File-lifecycle seam shared by repository transfers. Production uses the session-owned actor;
/// tests can inject explicit creation/protection/cleanup failures without replacing transport.
public protocol SensitiveFileWorking: Sendable {
    func makeWorkDirectory() async throws -> URL
    func makeSensitiveFile(in directory: URL, suggestedName: String) async throws -> URL
    func protectFile(at url: URL) async throws
    func removeWorkDirectory(_ directory: URL) async throws
}

/// Owns short-lived files that may contain decrypted credentials or attachment contents. The
/// actor confines filesystem operations, and its fixed app-owned root ensures stale cleanup never
/// recursively touches unrelated temporary files.
public actor SensitiveTemporaryFileStore: SensitiveFileWorking {
    private static let directoryName = "vaultwarden-sensitive-attachments"

    /// Shared process-wide owner so attachment work and session cleanup always address the same
    /// app-owned directory.
    public static let shared = SensitiveTemporaryFileStore(isAcceptingWork: false)

    private let fileManager: FileManager
    private var needsStaleCleanup = true
    private var isAcceptingWork: Bool
    public nonisolated let rootURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        isAcceptingWork = true
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    /// Root injection is reserved for isolated package tests; production callers use `shared`.
    @_spi(Testing)
    public init(fileManager: FileManager = .default, rootURL: URL) {
        self.fileManager = fileManager
        isAcceptingWork = true
        self.rootURL = rootURL
    }

    private init(fileManager: FileManager = .default, isAcceptingWork: Bool) {
        self.fileManager = fileManager
        self.isAcceptingWork = isAcceptingWork
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    /// Starts a new authenticated session after clearing files from any previous session.
    public func beginSession() throws {
        isAcceptingWork = false
        try removeOwnedRoot()
        needsStaleCleanup = false
        isAcceptingWork = true
    }

    /// Ends the current session and removes its work files. Further file creation is rejected until
    /// `beginSession()` is called. A symlink is removed as a link only; regular files are untouched.
    public func removeStaleWorkDirectories() throws {
        isAcceptingWork = false
        needsStaleCleanup = true
        try removeOwnedRoot()
        needsStaleCleanup = true
    }

    public func makeWorkDirectory() throws -> URL {
        guard isAcceptingWork else { throw SensitiveTemporaryFileStoreError.sessionInactive }
        if needsStaleCleanup {
            guard !isSymbolicLink(rootURL) else {
                try removeOwnedRoot()
                throw SensitiveTemporaryFileStoreError.unsafeRoot
            }
            try removeOwnedRoot()
            needsStaleCleanup = false
        }
        try ensureSafeRootDirectory()
        let directory = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try createDirectory(directory)
        return directory
    }

    /// Removes only the owned root. Symlinks are unlinked rather than followed; regular files are
    /// left untouched because this store never owns them.
    private func removeOwnedRoot() throws {
        if isSymbolicLink(rootURL) {
            do {
                try fileManager.removeItem(at: rootURL)
            } catch {
                throw SensitiveTemporaryFileStoreError.cleanupFailed
            }
            return
        }
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        guard isDirectory(rootURL) else { throw SensitiveTemporaryFileStoreError.unsafeRoot }
        do {
            try fileManager.removeItem(at: rootURL)
        } catch {
            throw SensitiveTemporaryFileStoreError.cleanupFailed
        }
    }

    /// Reserves a user-only file before crypto or Foundation writes any content into it.
    public func makeSensitiveFile(in directory: URL, suggestedName: String) throws -> URL {
        guard isWorkDirectory(directory) else { throw SensitiveTemporaryFileStoreError.invalidWorkDirectory }
        let url = directory.appendingPathComponent(sanitizedFileName(suggestedName), isDirectory: false)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw SensitiveTemporaryFileStoreError.invalidWorkDirectory
        }
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o600)]
        #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.complete
        #endif
        guard fileManager.createFile(
            atPath: url.path,
            contents: Data(),
            attributes: attributes
        ) else {
            throw SensitiveTemporaryFileStoreError.couldNotCreateFile
        }
        return url
    }

    /// Reapplies restrictive permissions after APIs that may replace rather than truncate the
    /// reserved output file. Symlink destinations are rejected before permissions are changed.
    public func protectFile(at url: URL) throws {
        guard isWorkDirectory(url.deletingLastPathComponent()), !isSymbolicLink(url) else {
            throw SensitiveTemporaryFileStoreError.invalidWorkDirectory
        }
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o600)]
        #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }

    public func removeWorkDirectory(containing file: URL) throws {
        try removeWorkDirectory(file.deletingLastPathComponent())
    }

    public func removeWorkDirectory(_ directory: URL) throws {
        guard directory.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL else {
            throw SensitiveTemporaryFileStoreError.invalidWorkDirectory
        }
        guard fileManager.fileExists(atPath: directory.path) || isSymbolicLink(directory) else { return }
        guard !isSymbolicLink(directory), isDirectory(directory) else {
            throw SensitiveTemporaryFileStoreError.invalidWorkDirectory
        }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw SensitiveTemporaryFileStoreError.cleanupFailed
        }
    }

    public nonisolated func sanitizedFileName(_ rawName: String) -> String {
        let invalid = rawName.isEmpty
            || rawName == "."
            || rawName == ".."
            || rawName.contains("/")
            || rawName.contains("\\")
            || rawName.contains("\"")
            || rawName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        return invalid ? "attachment" : rawName
    }

    private func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: url.path)
    }

    private func ensureSafeRootDirectory() throws {
        guard !isSymbolicLink(rootURL) else { throw SensitiveTemporaryFileStoreError.unsafeRoot }
        if !fileManager.fileExists(atPath: rootURL.path) {
            try createDirectory(rootURL)
            return
        }
        guard isDirectory(rootURL) else { throw SensitiveTemporaryFileStoreError.unsafeRoot }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: rootURL.path)
    }

    private func isWorkDirectory(_ directory: URL) -> Bool {
        directory.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL
            && !isSymbolicLink(directory)
            && isDirectory(directory)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
