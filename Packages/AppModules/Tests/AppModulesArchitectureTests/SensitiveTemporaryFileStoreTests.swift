import Foundation
import Testing
@_spi(Testing) import SecurityStorage

@Suite
struct SensitiveTemporaryFileStoreTests {
    @Test
    func workDirectoriesAndFilesAreUserOnlyAndConfinedToTheDedicatedRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultwarden-temp-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SensitiveTemporaryFileStore(rootURL: root)

        let directory = try await store.makeWorkDirectory()
        let file = try await store.makeSensitiveFile(in: directory, suggestedName: "report.pdf")

        #expect(directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        #expect(file.lastPathComponent == "report.pdf")
        #expect(permissions(of: directory) == 0o700)
        #expect(permissions(of: file) == 0o600)
    }

    @Test
    func unsafeFileNamesUseANeutralFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultwarden-temp-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SensitiveTemporaryFileStore(rootURL: root)

        #expect(store.sanitizedFileName("../") == "attachment")
        #expect(store.sanitizedFileName("bad\\name") == "attachment")
        #expect(store.sanitizedFileName("bad\nname") == "attachment")
    }

    @Test
    func staleCleanupOnlyRemovesTheDedicatedRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultwarden-temp-store-test-\(UUID().uuidString)", isDirectory: true)
        let store = SensitiveTemporaryFileStore(rootURL: root)
        _ = try await store.makeWorkDirectory()

        try await store.removeStaleWorkDirectories()

        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test
    func sessionCleanupRemovesAllRegisteredWorkDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultwarden-temp-store-test-\(UUID().uuidString)", isDirectory: true)
        let store = SensitiveTemporaryFileStore(rootURL: root)
        let workDirectory = try await store.makeWorkDirectory()
        let file = try await store.makeSensitiveFile(in: workDirectory, suggestedName: "preview.pdf")

        try await store.removeStaleWorkDirectories()

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test
    func aSymbolicLinkAtTheDedicatedRootIsNeverFollowed() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let root = temporaryDirectory.appendingPathComponent("vaultwarden-temp-store-test-\(UUID().uuidString)")
        let destination = temporaryDirectory.appendingPathComponent("vaultwarden-temp-destination-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: destination)
        let store = SensitiveTemporaryFileStore(rootURL: root)

        var rejectedUnsafeRoot = false
        do {
            _ = try await store.makeWorkDirectory()
        } catch is SensitiveTemporaryFileStoreError {
            rejectedUnsafeRoot = true
        }
        #expect(rejectedUnsafeRoot)
        #expect(FileManager.default.fileExists(atPath: destination.path))

        try await store.removeStaleWorkDirectories()
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    private func permissions(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
