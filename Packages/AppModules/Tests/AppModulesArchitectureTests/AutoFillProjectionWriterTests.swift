import AutoFillContract
import Data
import Foundation
import Testing

@Suite
struct AutoFillProjectionWriterTests {
    @Test
    func successfulProjectionIsRevisionedAndExcludesDeletedRecords() async throws {
        let store = InMemoryProjectionStore()
        let writer = AutoFillProjectionWriter(
            accountID: "account-1", fileStore: store, now: { .distantFuture }
        )
        let active = EncryptedLoginRecord(
            id: "active",
            deletedAt: nil,
            encryptedCipherPayload: Foundation.Data("active".utf8)
        )
        let deleted = EncryptedLoginRecord(
            id: "deleted",
            deletedAt: .distantPast,
            encryptedCipherPayload: Foundation.Data("deleted".utf8)
        )

        let health = await writer.project(
            revision: 7,
            encryptedLoginRecords: [active, deleted],
            encryptedOrganizationKeys: ["org": "encrypted-key"]
        )
        let data = try #require(store.data)
        let envelope = try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: data)

        #expect(health == .current(revision: 7))
        #expect(envelope.accountID == "account-1")
        #expect(envelope.revision == 7)
        #expect(envelope.generatedAt == .distantFuture)
        #expect(envelope.encryptedLoginRecords.map(\.id) == ["active"])
        #expect(envelope.encryptedOrganizationKeys == ["org": "encrypted-key"])
    }

    @Test
    func olderRevisionNeverOverwritesACurrentProjection() async throws {
        let store = InMemoryProjectionStore(data: try encodedEnvelope(accountID: "account-1", revision: 9))
        let writer = AutoFillProjectionWriter(accountID: "account-1", fileStore: store)

        let health = await writer.project(revision: 8, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])

        #expect(health == .current(revision: 9))
        #expect(store.replaceCalls == 0)
        #expect(try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: #require(store.data)).revision == 9)
    }

    @Test
    func readFailureRetriesInitializationAndPreservesTheNewerProjection() async throws {
        let original = try encodedEnvelope(accountID: "account-1", revision: 9)
        let store = InMemoryProjectionStore(data: original)
        store.readFailuresRemaining = 1
        let writer = AutoFillProjectionWriter(accountID: "account-1", fileStore: store)

        let firstHealth = await writer.project(revision: 1, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])
        let secondHealth = await writer.project(revision: 1, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])

        #expect(firstHealth == .unavailable)
        #expect(secondHealth == .current(revision: 9))
        #expect(store.replaceCalls == 0)
        #expect(store.data == original)
    }

    @Test
    func foreignProjectionCleanupFailureRetriesBeforeWriting() async throws {
        let store = InMemoryProjectionStore(data: try encodedEnvelope(accountID: "old-account", revision: 20))
        store.removeFailuresRemaining = 1
        let writer = AutoFillProjectionWriter(accountID: "new-account", fileStore: store)

        let firstHealth = await writer.project(revision: 1, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])
        let secondHealth = await writer.project(revision: 1, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])
        let written = try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: #require(store.data))

        #expect(firstHealth == .unavailable)
        #expect(secondHealth == .current(revision: 1))
        #expect(store.removeCalls == 2)
        #expect(store.replaceCalls == 1)
        #expect(written.accountID == "new-account")
        #expect(written.revision == 1)
    }

    @Test
    func corruptProjectionIsRemovedBeforeReplacement() async throws {
        let store = InMemoryProjectionStore(data: Foundation.Data("corrupt".utf8))
        let writer = AutoFillProjectionWriter(accountID: "account-1", fileStore: store)

        let health = await writer.project(revision: 1, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])

        #expect(health == .current(revision: 1))
        #expect(store.removeCalls == 1)
        #expect(store.replaceCalls == 1)
        #expect(
            try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: #require(store.data)).revision == 1
        )
    }

    @Test
    func failedReplacementPreservesPriorProjectionAndMarksItStale() async throws {
        let original = try encodedEnvelope(accountID: "account-1", revision: 4)
        let store = InMemoryProjectionStore(data: original)
        store.replaceError = TestProjectionError.replaceFailed
        let writer = AutoFillProjectionWriter(accountID: "account-1", fileStore: store)

        let health = await writer.project(revision: 5, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])

        #expect(health == .stale(lastSuccessfulRevision: 4))
        #expect(store.data == original)
        #expect(store.replaceCalls == 1)
    }

    @Test
    func encodingFailurePreservesPriorProjectionAndMarksItStale() async throws {
        let original = try encodedEnvelope(accountID: "account-1", revision: 2)
        let store = InMemoryProjectionStore(data: original)
        let writer = AutoFillProjectionWriter(
            accountID: "account-1", fileStore: store, encoding: FailingProjectionEncoding()
        )

        let health = await writer.project(revision: 3, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])

        #expect(health == .stale(lastSuccessfulRevision: 2))
        #expect(store.data == original)
        #expect(store.replaceCalls == 0)
    }

    @Test
    func accountSwitchRemovesForeignProjectionBeforeWritingTheNewOne() async throws {
        let store = InMemoryProjectionStore(data: try encodedEnvelope(accountID: "old-account", revision: 20))
        let writer = AutoFillProjectionWriter(accountID: "new-account", fileStore: store)

        let health = await writer.project(revision: 1, encryptedLoginRecords: [], encryptedOrganizationKeys: [:])

        #expect(health == .current(revision: 1))
        #expect(store.removeCalls == 1)
        #expect(
            try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: #require(store.data)).accountID == "new-account"
        )
    }

    @Test
    func atomicFileStoreReplacesTheFinalFileWithoutLeavingTemporaryFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultwarden-projection-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AtomicAutoFillProjectionFileStore(directoryURL: directory)

        try store.replaceProjectionAtomically(with: Foundation.Data("first".utf8))
        try store.replaceProjectionAtomically(with: Foundation.Data("second".utf8))

        #expect(try store.readProjection() == Foundation.Data("second".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["autofill-cache-v1.json"])
    }

    private func encodedEnvelope(accountID: String, revision: UInt64) throws -> Foundation.Data {
        try JSONEncoder().encode(AutoFillCacheEnvelope(
            accountID: accountID,
            revision: revision,
            generatedAt: .distantPast,
            encryptedLoginRecords: [],
            encryptedOrganizationKeys: [:]
        ))
    }
}

private enum TestProjectionError: Error {
    case replaceFailed
    case encodingFailed
    case readFailed
    case removeFailed
}

private final class InMemoryProjectionStore: AutoFillProjectionFileStore, @unchecked Sendable {
    var data: Foundation.Data?
    var replaceError: Error?
    var readFailuresRemaining = 0
    var removeFailuresRemaining = 0
    private(set) var replaceCalls = 0
    private(set) var removeCalls = 0

    init(data: Foundation.Data? = nil) {
        self.data = data
    }

    func readProjection() throws -> Foundation.Data? {
        if readFailuresRemaining > 0 {
            readFailuresRemaining -= 1
            throw TestProjectionError.readFailed
        }
        return data
    }

    func replaceProjectionAtomically(with data: Foundation.Data) throws {
        replaceCalls += 1
        if let replaceError { throw replaceError }
        self.data = data
    }

    func removeProjection() throws {
        removeCalls += 1
        if removeFailuresRemaining > 0 {
            removeFailuresRemaining -= 1
            throw TestProjectionError.removeFailed
        }
        data = nil
    }
}

private struct FailingProjectionEncoding: AutoFillProjectionEncoding {
    func encode(_ envelope: AutoFillCacheEnvelope) throws -> Foundation.Data {
        throw TestProjectionError.encodingFailed
    }

    func decode(_ data: Foundation.Data) throws -> AutoFillCacheEnvelope {
        try JSONDecoder().decode(AutoFillCacheEnvelope.self, from: data)
    }
}
