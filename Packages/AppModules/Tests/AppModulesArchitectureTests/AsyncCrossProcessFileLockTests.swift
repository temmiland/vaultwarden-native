import Darwin
import Foundation
@testable import SecurityStorage
import Testing

@Suite
struct AsyncCrossProcessFileLockTests {
    @Test
    func missingLiveContainerNeverRunsAnUncoordinatedOperation() async throws {
        let lock = AsyncCrossProcessFileLock(containerURL: nil, filename: ".identities.lock")
        await #expect(throws: CrossProcessFileLockError.missingContainer) {
            try await lock.withExclusiveLock { Issue.record("Missing container bypassed lock") }
        }
    }

    @Test(arguments: ["", ".", "..", "../escape", "nested/file", "nested\\file", "nul\0name"])
    func invalidFilenameCannotEscapeContainer(_ filename: String) async throws {
        await #expect(throws: CrossProcessFileLockError.invalidFilename) {
            try await AsyncCrossProcessFileLock(containerURL: nil, filename: filename).withExclusiveLock { Issue.record(
                "Invalid lock filename"
            ) }
        }
    }

    @Test(arguments: ["url", "missing", "symlink", "directory", "fifo"])
    func unsafeOrUnavailableLockFilesNeverReachMutation(_ scenario: String) async throws {
        let directory = try Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(".identities.lock")
        switch scenario {
        case "symlink": try FileManager.default.createSymbolicLink(
                at: file,
                withDestinationURL: directory.appendingPathComponent("uncreated")
            )
        case "directory": try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        case "fifo": #expect(mkfifo(file.path, S_IRUSR | S_IWUSR) == 0)
        default: break
        }
        let container = scenario == "url" ? URL(string: "https://example.invalid")! : (
            scenario == "missing" ? directory.appendingPathComponent("missing") : directory
        )
        await #expect(throws: (any Error).self) {
            try await AsyncCrossProcessFileLock(containerURL: container, filename: ".identities.lock").withExclusiveLock { Issue.record(
                "Unsafe lock file reached mutation"
            ) }
        }
        if scenario == "symlink" { #expect(
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent("uncreated").path)
        ) }
    }

    @Test
    func independentDescriptorsSerializeAcrossAwaitAndThrowReleasesLock() async throws {
        let directory = try Self.directory(), gate = AuthOperationTestGate(), waiting = IdentityMutationContentionProbe(), access = PasskeyRecoveryAccessFixture(
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AsyncCrossProcessFileLock(containerURL: directory, filename: ".identities.lock")
        let second = AsyncCrossProcessFileLock(
            containerURL: directory,
            filename: ".identities.lock",
            waitingLimit: .seconds(10),
            onContention: { waiting.record() }
        )
        let task = Task { try await first.withExclusiveLock { await gate.pause(); throw PasskeyRecoveryFixtureError.write } }
        await gate.waitUntilPaused()
        let other = Task { try await second.withExclusiveLock { access.project(AutoFillQuerySourceFixture.dto("saved")); return 42 } }
        await waiting.wait()
        #expect(access.projectionCount == 0)
        await gate.release()
        await #expect(throws: PasskeyRecoveryFixtureError.write) { try await task.value }
        #expect(try await other.value == 42 && access.projectionCount == 1)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(".identities.lock").path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test
    func cancellationWhileWaitingDoesNotEnterAndDoesNotRequireOwnerToFinish() async throws {
        let directory = try Self.directory(), gate = AuthOperationTestGate(), waiting = IdentityMutationContentionProbe()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = AsyncCrossProcessFileLock(containerURL: directory, filename: ".identities.lock")
        let contender = AsyncCrossProcessFileLock(
            containerURL: directory,
            filename: ".identities.lock",
            waitingLimit: .seconds(10),
            onContention: { waiting.record() }
        )
        let task = Task { try await owner.withExclusiveLock { await gate.pause() } }
        await gate.waitUntilPaused()
        let cancelled = Task { try await contender.withExclusiveLock { Issue.record("Cancelled waiter entered") } }
        await waiting.wait(); cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        await gate.release(); try await task.value
        #expect(try await contender.withExclusiveLock { 7 } == 7)
    }

    @Test
    func timeoutBoundsWaitingButNeverExpiresTheOwnersLease() async throws {
        let directory = try Self.directory(), gate = AuthOperationTestGate()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = AsyncCrossProcessFileLock(
            containerURL: directory,
            filename: ".identities.lock",
            waitingLimit: .nanoseconds(1)
        )
        let owner = Task { try await lock.withExclusiveLock { await gate.pause() } }
        await gate.waitUntilPaused()
        await #expect(throws: AsyncCrossProcessFileLockError.timedOut) {
            try await lock.withExclusiveLock { Issue.record("Timeout expired owner's lock") }
        }
        await gate.release(); try await owner.value
        #expect(try await lock.withExclusiveLock { 8 } == 8)
    }

    @Test
    func cancellationOfAcquiredConsumerKeepsBatchExclusiveUntilConfirmation() async throws {
        let directory = try Self.directory(), gate = AuthOperationTestGate(), waiting = IdentityMutationContentionProbe(), access = PasskeyRecoveryAccessFixture(
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = AsyncCrossProcessFileLock(containerURL: directory, filename: ".identities.lock")
        let contender = AsyncCrossProcessFileLock(
            containerURL: directory,
            filename: ".identities.lock",
            waitingLimit: .seconds(10),
            onContention: { waiting.record() }
        )
        let task = Task { try await owner.withExclusiveLock { await gate.pause(); access.project(
            AutoFillQuerySourceFixture.dto("saved")
        ); return "confirmed" } }
        await gate.waitUntilPaused(); task.cancel()
        let other = Task { try await contender.withExclusiveLock { #expect(access.projectionCount == 1) } }
        await waiting.wait()
        #expect(access.projectionCount == 0)
        await gate.release()
        #expect(try await task.value == "confirmed")
        try await other.value
    }

    private static func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("async-identity-lock-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
