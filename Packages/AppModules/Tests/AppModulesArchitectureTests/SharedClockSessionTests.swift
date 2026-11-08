import Foundation
@testable import SecurityStorage
import Testing

@Suite
struct SharedClockSessionTests {
    #if os(macOS)
        @Test
        func aSeparateLiveProcessCanCarryContinuityButItsExitCannotResurrectTheLease() throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            var issuer: SharedClockSessionRegistry? = SharedClockSessionRegistry()
            let original = try #require(issuer).currentID(containerURL: directory)
            let process = Process(), input = Pipe(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", """
            import fcntl, sys, select
            with open(sys.argv[1], 'r+b') as handle:
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass
                else:
                    sys.exit(2)
                fcntl.flock(handle, fcntl.LOCK_SH | fcntl.LOCK_NB)
                print('r', flush=True)
                select.select([sys.stdin], [], [], 15)
            """, directory.appendingPathComponent(".vaultwarden-clock-\(original.uuidString).lease").path]
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            defer {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
            }
            #expect(try output.fileHandleForReading.read(upToCount: 1) == Data("r".utf8))
            issuer = nil
            var observer: SharedClockSessionRegistry? = SharedClockSessionRegistry()
            #expect(try #require(observer).currentID(containerURL: directory) == original)
            observer = nil
            try input.fileHandleForWriting.write(contentsOf: Data("x".utf8))
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(try SharedClockSessionRegistry().currentID(containerURL: directory) != original)
        }
    #endif

    @Test
    func independentParticipantsJoinOneLiveClockDomainAndLastExitInvalidatesIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var issuer: SharedClockSessionRegistry? = SharedClockSessionRegistry()
        let first = try #require(issuer).currentID(containerURL: directory)
        var observer: SharedClockSessionRegistry? = SharedClockSessionRegistry()
        #expect(try #require(observer).currentID(containerURL: directory) == first)
        issuer = nil
        #expect(try #require(observer).currentID(containerURL: directory) == first)
        observer = nil
        let restarted = SharedClockSessionRegistry()
        #expect(try restarted.currentID(containerURL: directory) != first)
    }

    @Test
    func persistedIdentifierAndFileCannotRecreateADeadKernelAnchor() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var previous: UUID!
        do {
            let process = SharedClockSessionRegistry()
            previous = try process.currentID(containerURL: directory)
        }
        // Both files survived. Their presence alone must never authorize a persisted deadline.
        #expect(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(".vaultwarden-clock-session.id").path
            )
        )
        let next = SharedClockSessionRegistry()
        #expect(try next.currentID(containerURL: directory) != previous)
    }

    @Test
    func aSymlinkCannotRedirectClockSessionCoordination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("unrelated")
        try Data("unchanged".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent(".vaultwarden-clock-session.lock"), withDestinationURL: target
        )
        #expect(throws: SharedClockSessionError.self) {
            try SharedClockSessionRegistry().currentID(containerURL: directory)
        }
        #expect(try Data(contentsOf: target) == Data("unchanged".utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
