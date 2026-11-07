import Foundation
@testable import Networking
import Testing

@Suite
struct HTTPDownloadedFileInstallerTests {
    private struct Fixture {
        let directory: URL
        var input: URL { directory.appendingPathComponent("download") }
        var output: URL { directory.appendingPathComponent("destination") }
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "download-install-\(UUID().uuidString)"
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try Data("downloaded".utf8).write(to: input)
        }

        func remove() { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(
            "Fixture cleanup failed"
        ) } }
        func entries() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) }
    }

    @Test(arguments: [false, true])
    func publishesCompleteFileWithRestrictivePermissions(_ existing: Bool) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        if existing { try Data("old".utf8).write(to: fixture.output) }
        try HTTPDownloadedFileInstaller.install(fixture.input, at: fixture.output)
        #expect(try Data(contentsOf: fixture.output) == Data("downloaded".utf8))
        #expect(try fixture.entries() == ["download", "destination"])
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.output.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test(arguments: [false, true])
    func cancellationBeforePublicationPreservesDestinationAndRemovesStage(_ existing: Bool) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        if existing { try Data("old".utf8).write(to: fixture.output) }
        var checks = 0
        #expect(throws: CancellationError.self) {
            try HTTPDownloadedFileInstaller.install(fixture.input, at: fixture.output, checkCancellation: {
                checks += 1
                if checks == 2 { throw CancellationError() }
            })
        }
        #expect(checks == 2)
        #expect(try fixture.entries() == (existing ? ["download", "destination"] : ["download"]))
        if existing { #expect(try Data(contentsOf: fixture.output) == Data("old".utf8)) }
    }

    @Test(arguments: ["directory", "symlink", "broken-symlink"])
    func refusesUnsafeDestinationsWithoutChangingOtherFiles(_ kind: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        if kind == "directory" {
            try FileManager.default.createDirectory(at: fixture.output, withIntermediateDirectories: false)
        } else {
            try FileManager.default.createSymbolicLink(
                at: fixture.output,
                withDestinationURL: kind == "symlink" ? fixture.input : fixture.directory.appendingPathComponent(
                    "missing"
                )
            )
        }
        #expect(throws: HTTPFileTransferError.invalidDestination) {
            try HTTPDownloadedFileInstaller.install(fixture.input, at: fixture.output)
        }
        #expect(try Data(contentsOf: fixture.input) == Data("downloaded".utf8))
        #expect(try fixture.entries() == ["download", "destination"])
    }

    @Test
    func missingParentIsAnErrorNotAnInMemoryFallback() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        #expect(throws: (any Error).self) {
            try HTTPDownloadedFileInstaller.install(
                fixture.input,
                at: fixture.directory.appendingPathComponent("missing/destination")
            )
        }
        #expect(try fixture.entries() == ["download"])
    }
}
