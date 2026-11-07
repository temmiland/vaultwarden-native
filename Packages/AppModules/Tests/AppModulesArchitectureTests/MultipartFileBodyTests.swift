import Darwin
import Foundation
import Networking
import Testing

@Suite
struct MultipartFileBodyTests {
    private struct Fixture {
        let directory: URL
        var input: URL { directory.appendingPathComponent("input") }
        var output: URL { directory.appendingPathComponent("body") }
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "multipart-test-\(UUID().uuidString)"
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }

        func remove() { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(
            "Fixture cleanup failed"
        ) } }
        func build(
            _ name: String = "name.bin",
            boundary: String = "test-boundary",
            check: () throws -> Void = {}
        ) throws -> MultipartFileBody {
            try MultipartFileBody.prepare(
                inputURL: input,
                outputURL: output,
                fileName: name,
                boundary: boundary,
                checkAccess: check
            )
        }
    }

    @Test(arguments: ["name.bin", "../nested/name", "bad\"\r\nInjected: true", "bad\\name", ".", ""])
    func smallFileHasExactFramingAndSafeName(_ name: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let bytes = Data([0, 1, 2, 255])
        try bytes.write(to: fixture.input)
        let body = try fixture.build(name)
        let output = try Data(contentsOf: body.fileURL)
        let expectedName = name == "name.bin" ? name : name == "../nested/name" ? "name" : "attachment"
        var expected = Data(
            "--test-boundary\r\nContent-Disposition: form-data; name=\"data\"; filename=\"\(expectedName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8
        )
        expected.append(bytes)
        expected.append(Data("\r\n--test-boundary--\r\n".utf8))
        #expect(output == expected)
        #expect(body.byteCount == UInt64(expected.count))
        #expect(body.contentType == "multipart/form-data; boundary=test-boundary")
        #expect(try Data(contentsOf: fixture.input) == bytes)
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: fixture.output.path)[.posixPermissions] as? NSNumber
        )
        #expect(mode.intValue & 0o777 == 0o600)
    }

    @Test
    func sparseLargeFileCopiesInBoundedChunksWithUInt64Size() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        #expect(FileManager.default.createFile(atPath: fixture.input.path, contents: nil))
        let file = try FileHandle(forWritingTo: fixture.input)
        let size: UInt64 = 16 * 1_024 * 1_024 + 3
        try file.truncate(atOffset: size)
        try file.close()
        var checks = 0
        let body = try fixture.build(check: { checks += 1 })
        let emptyOverhead: UInt64 = 146 // exact framing for name.bin / test-boundary
        #expect(body.byteCount == size + emptyOverhead)
        #expect(
            checks == Int((size + UInt64(MultipartFileBody.chunkSize) - 1) / UInt64(MultipartFileBody.chunkSize)) + 3
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: body.fileURL.path)
        #expect((attributes[.size] as? NSNumber)?.uint64Value == body.byteCount)
        // No Data(contentsOf:) for either large file: only a tiny suffix inspection.
        let reader = try FileHandle(forReadingFrom: body.fileURL)
        try reader.seek(toOffset: body.byteCount - 21)
        #expect(try reader.readToEnd() == Data("\r\n--test-boundary--\r\n".utf8))
        try reader.close()
    }

    @Test
    func opaqueEncryptedSendFilenamePreservesSlashSeparators() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data([1, 2, 3]).write(to: fixture.input)
        let encryptedName = "2.+abc/def==|3/ghi==|jkl/mno=="
        let body = try MultipartFileBody.prepare(
            inputURL: fixture.input,
            outputURL: fixture.output,
            fileName: encryptedName,
            boundary: "test-boundary",
            preserveSlashesInFileName: true
        )
        let output = try String(contentsOf: fixture.output, encoding: .utf8)
        #expect(output.contains("filename=\"\(encryptedName)\""))
        #expect(body.byteCount == UInt64(try Data(contentsOf: fixture.output).count))
    }

    @Test
    func longOpaqueEncryptedFilenameIsNeverReplaced() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data([1, 2, 3]).write(to: fixture.input)
        let name = "2." + String(repeating: "ab/c", count: 100) + "|mac"
        _ = try MultipartFileBody.prepare(
            inputURL: fixture.input, outputURL: fixture.output, fileName: name,
            boundary: "test-boundary", preserveSlashesInFileName: true
        )
        let body = try String(contentsOf: fixture.output, encoding: .utf8)
        #expect(body.contains("filename=\"\(name)\""))
    }

    @Test
    func emptyFileStillProducesCompleteMultipartBody() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data().write(to: fixture.input)
        let body = try fixture.build()
        #expect(body.byteCount == UInt64(try Data(contentsOf: fixture.output).count))
    }

    @Test(arguments: ["bad\r\nBoundary", "", String(repeating: "a", count: 71)])
    func invalidBoundaryCannotCreateOutput(_ boundary: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data().write(to: fixture.input)
        #expect(throws: MultipartFileBodyError.invalidBoundary) { try fixture.build(boundary: boundary) }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @Test(arguments: ["file", "symlink"])
    func existingDestinationIsNeverOverwritten(_ kind: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data("original".utf8).write(to: fixture.input)
        if kind == "file" { try Data("keep".utf8).write(to: fixture.output) }
        else { try FileManager.default.createSymbolicLink(at: fixture.output, withDestinationURL: fixture.input) }
        #expect(throws: MultipartFileBodyError.couldNotCreateFile) { try fixture.build() }
        #expect(try Data(contentsOf: fixture.input) == Data("original".utf8))
        #expect(try Data(contentsOf: fixture.output) == Data((kind == "file" ? "keep" : "original").utf8))
    }

    @Test(arguments: ["symlink", "directory", "fifo", "missing"])
    func unsafeInputIsRejectedBeforeOutputCreation(_ kind: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        switch kind {
        case "symlink": try FileManager.default.createSymbolicLink(
                at: fixture.input,
                withDestinationURL: fixture.directory
            )
        case "directory": try FileManager.default.createDirectory(at: fixture.input, withIntermediateDirectories: false)
        case "fifo": #expect(mkfifo(fixture.input.path, 0o600) == 0)
        default: break
        }
        #expect(throws: MultipartFileBodyError.unsafeFile) { try fixture.build() }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @Test(arguments: [false, true])
    func cancellationOrRevocationDuringCopyRemovesPartialBody(_ cancelled: Bool) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data(repeating: 7, count: MultipartFileBody.chunkSize * 3).write(to: fixture.input)
        var checks = 0
        do {
            _ = try fixture.build(check: {
                checks += 1
                if checks == 3 {
                    if cancelled { throw CancellationError() }
                    throw MultipartFileBodyError.unsafeFile
                }
            })
            Issue.record("Expected copy rejection")
        } catch {
            #expect(cancelled ? error is CancellationError : error as? MultipartFileBodyError == .unsafeFile)
        }
        #expect(checks == 3)
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @Test
    func truncatedSourceDoesNotSubmitAnIncompleteBody() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data("before".utf8).write(to: fixture.input)
        var checks = 0
        #expect(throws: MultipartFileBodyError.unsafeFile) {
            try fixture.build(check: {
                checks += 1
                if checks == 2 {
                    let handle = try FileHandle(forWritingTo: fixture.input)
                    try handle.truncate(atOffset: 0); try handle.close()
                }
            })
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }
}
