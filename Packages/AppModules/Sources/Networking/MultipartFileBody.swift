import Darwin
import Foundation

public enum MultipartFileBodyError: Error, Sendable, Equatable {
    case invalidBoundary
    case unsafeFile
    case couldNotCreateFile
    case cleanupFailed
    case invalidFileName
}

/// Builds a multipart upload using bounded chunks, never a Data containing the complete file.
/// The caller owns both paths in its protected work directory and MUST clean that directory
/// after success/failure. This bounds transport assembly, not upstream SDK encryption memory.
public struct MultipartFileBody: Sendable {
    public let fileURL: URL
    public let contentType: String
    public let byteCount: UInt64
    public static let chunkSize = 64 * 1_024

    public static func prepare(
        inputURL: URL,
        outputURL: URL,
        fileName: String,
        boundary: String,
        preserveSlashesInFileName: Bool = false,
        checkAccess: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> Self {
        try Task.checkCancellation()
        try checkAccess()
        if preserveSlashesInFileName {
            guard !fileName.isEmpty, fileName.utf8.allSatisfy({
                (0x21 ... 0x7E).contains($0) && $0 != 0x22 && $0 != 0x5C
            }) else { throw MultipartFileBodyError.invalidFileName }
        }
        guard !boundary.isEmpty, boundary.utf8.count <= 70,
              boundary.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 90).contains($0) ||
                      (97 ... 122).contains($0) || $0 == 45 }) else {
            throw MultipartFileBodyError.invalidBoundary
        }
        guard inputURL.isFileURL, outputURL.isFileURL,
              inputURL.standardizedFileURL != outputURL.standardizedFileURL else {
            throw MultipartFileBodyError.unsafeFile
        }
        // O_NONBLOCK prevents a substituted FIFO from blocking before regular-file validation.
        let inputFD = open(inputURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard inputFD >= 0 else { throw MultipartFileBodyError.unsafeFile }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(inputFD, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0 else { throw MultipartFileBodyError.unsafeFile }
        let outputFD = open(outputURL.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard outputFD >= 0 else { throw MultipartFileBodyError.couldNotCreateFile }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        do {
            #if os(iOS)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: outputURL.path
                )
            #endif
            let name = sanitizedFileName(fileName, preserveSlashes: preserveSlashesInFileName)
            let prefix = Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"data\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8
            )
            let suffix = Data("\r\n--\(boundary)--\r\n".utf8)
            try output.write(contentsOf: prefix)
            var copied: UInt64 = 0
            while true {
                try Task.checkCancellation()
                try checkAccess()
                let bytes = try input.read(upToCount: chunkSize) ?? Data()
                if bytes.isEmpty { break }
                // The encrypted source is immutable during assembly. Reject truncation/growth;
                // permission/session checks still run immediately before network submission.
                guard copied <= UInt64(metadata.st_size),
                      UInt64(bytes.count) <= UInt64(metadata.st_size) - copied else {
                    throw MultipartFileBodyError.unsafeFile
                }
                try output.write(contentsOf: bytes)
                copied += UInt64(bytes.count)
            }
            guard copied == UInt64(metadata.st_size) else { throw MultipartFileBodyError.unsafeFile }
            try Task.checkCancellation()
            try checkAccess()
            try output.write(contentsOf: suffix)
            try output.synchronize()
            try output.close()
            try input.close()
            return Self(
                fileURL: outputURL,
                contentType: "multipart/form-data; boundary=\(boundary)",
                byteCount: UInt64(prefix.count) + copied + UInt64(suffix.count)
            )
        } catch {
            // Handles own their FDs even on a throwing path. Never silently retain a partial
            // upload body; a failed unlink has its own typed repair error.
            do { try FileManager.default.removeItem(at: outputURL) }
            catch { throw MultipartFileBodyError.cleanupFailed }
            throw error
        }
    }

    private static func sanitizedFileName(_ value: String, preserveSlashes: Bool) -> String {
        guard !value.isEmpty, !value.contains("\""), !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return "attachment"
        }
        // User-supplied filesystem names are reduced to a basename. A Bitwarden encrypted Send
        // filename is opaque ciphertext and Vaultwarden requires the exact encrypted value in
        // the multipart part; slashes inside that value are data, not filesystem path components.
        if preserveSlashes { return value }
        let name = value.split(separator: "/").last.map(String.init) ?? ""
        return name.isEmpty || name == "." || name == ".." || name.utf8.count > 255 ? "attachment" : name
    }
}
