import Foundation

let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || arguments == ["--history"] else {
    fatalError("Usage: swift Scripts/check-source-secrets.swift [--history]")
}

let scansHistory = arguments == ["--history"]

let patterns = [
    #"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"#,
    #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
    #"\bgh[pousr]_[A-Za-z0-9]{30,}\b"#,
    #"\bgithub_pat_[A-Za-z0-9_]{40,}\b"#,
    #"\bglpat-[A-Za-z0-9_-]{20,}\b"#,
    #"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"#,
    #"\bnpm_[A-Za-z0-9]{36}\b"#,
    #"\bpypi-[A-Za-z0-9_-]{50,}\b"#,
    #"\bAIza[0-9A-Za-z_-]{35}\b"#,
    #"\b(?:sk|rk)_live_[0-9A-Za-z]{20,}\b"#,
]
let expressions = try patterns.map { try NSRegularExpression(pattern: $0) }

func containsCredential(_ text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    return expressions.contains { $0.firstMatch(in: text, range: range) != nil }
}

func runGit(_ arguments: [String], input: Data = Data()) throws -> Data {
    let fileManager = FileManager.default
    let nonce = UUID().uuidString
    let inputURL = fileManager.temporaryDirectory.appendingPathComponent("vw-secret-scan-\(nonce)-in")
    let outputURL = fileManager.temporaryDirectory.appendingPathComponent("vw-secret-scan-\(nonce)-out")
    defer {
        try? fileManager.removeItem(at: inputURL)
        try? fileManager.removeItem(at: outputURL)
    }
    guard fileManager.createFile(atPath: inputURL.path, contents: input, attributes: [.posixPermissions: 0o600]),
          fileManager.createFile(atPath: outputURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    else { throw CocoaError(.fileWriteUnknown) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = repository
    process.standardInput = try FileHandle(forReadingFrom: inputURL)
    process.standardOutput = try FileHandle(forWritingTo: outputURL)
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
    return try Data(contentsOf: outputURL)
}

let listingProcess = Process(), listingOutput = Pipe()
listingProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
listingProcess.arguments = ["ls-files", "-z", "--cached", "--others", "--exclude-standard"]
listingProcess.currentDirectoryURL = repository
listingProcess.standardOutput = listingOutput
try listingProcess.run()
let listing = listingOutput.fileHandleForReading.readDataToEndOfFile()
listingProcess.waitUntilExit()
guard listingProcess.terminationStatus == 0 else { fatalError("Cannot enumerate source files") }

var matches = 0, checked = 0
for path in String(decoding: listing, as: UTF8.self).split(separator: "\0").map(String.init) {
    // Include generated sources and new, not-yet-staged source files. Ignored local signing,
    // caches and binaries are excluded by Git. Matching contents are never printed.
    // Decode every UTF-8 source file, including LICENSE, dotfiles and bundled datasets; an
    // extension allowlist would silently miss these. Binary assets are inventoried separately.
    guard let text = try? String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8) else { continue }
    checked += 1
    if containsCredential(text) {
        FileHandle.standardError.write(Data("Potential credential in source: \(path) (content withheld)\n".utf8))
        matches += 1
    }
}

var historyChecked = 0
if scansHistory {
    let objectListing = try runGit(["rev-list", "--objects", "--all"])
    let pathsByObject = Dictionary(
        String(decoding: objectListing, as: UTF8.self).split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let object = parts.first else { return nil }
            return (String(object), parts.count == 2 ? String(parts[1]) : "<unknown path>")
        },
        uniquingKeysWith: { first, _ in first }
    )
    let objectIDs = pathsByObject.keys.sorted()
    let objectInput = Data(objectIDs.joined(separator: "\n").appending("\n").utf8)
    let checkedObjects = try runGit(["cat-file", "--batch-check=%(objectname) %(objecttype)"], input: objectInput)
    let blobIDs = String(decoding: checkedObjects, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
        let fields = line.split(separator: " ")
        guard fields.count == 2, fields[1] == "blob" else { return nil }
        return String(fields[0])
    }
    let blobs: Data
    if blobIDs.isEmpty {
        blobs = Data()
    } else {
        let blobInput = Data(blobIDs.joined(separator: "\n").appending("\n").utf8)
        blobs = try runGit(["cat-file", "--batch"], input: blobInput)
    }
    var offset = 0
    while offset < blobs.count {
        guard let headerEnd = blobs[offset...].firstIndex(of: 0x0A) else { throw CocoaError(.fileReadCorruptFile) }
        let header = String(decoding: blobs[offset ..< headerEnd], as: UTF8.self).split(separator: " ")
        guard header.count == 3, header[1] == "blob", let byteCount = Int(header[2]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let bodyStart = headerEnd + 1
        let bodyEnd = bodyStart + byteCount
        guard bodyEnd < blobs.count else { throw CocoaError(.fileReadCorruptFile) }
        let body = blobs[bodyStart ..< bodyEnd]
        offset = bodyEnd + 1
        guard let text = String(data: body, encoding: .utf8) else { continue }
        historyChecked += 1
        guard containsCredential(text), let object = header.first,
              let path = pathsByObject[String(object)] else { continue }
        FileHandle.standardError.write(
            Data("Potential credential in reachable Git history: \(path) (content withheld)\n".utf8)
        )
        matches += 1
    }
}

guard matches == 0 else { exit(1) }
let historySummary = scansHistory ? "; \(historyChecked) reachable history text blobs" : ""
print(
    "Source credential-pattern check passed (\(checked) tracked/unignored text files\(historySummary)). This is a heuristic, not a security audit."
)
