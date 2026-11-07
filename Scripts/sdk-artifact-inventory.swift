import CryptoKit
import Foundation

/// File-byte inventory, not an attestation of provenance or reproducible builds. Reads only
/// the explicitly named XCFramework, never Keychain, vault cache or user credentials.
struct Entry: Codable, Equatable {
    let path: String
    let bytes: UInt64
    let sha256: String
}

struct Inventory: Codable, Equatable {
    let schemaVersion: Int
    let files: [Entry]
    let contentSHA256: String
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1 || (arguments.count == 3 && arguments[1] == "--verify") else {
    fatalError("Usage: swift Scripts/sdk-artifact-inventory.swift FRAMEWORK [--verify MANIFEST.json]")
}

let root = URL(fileURLWithPath: arguments[0], isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
guard root.lastPathComponent == "BitwardenFFI.xcframework",
      let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
      ) else {
    fatalError("Expected an existing BitwardenFFI.xcframework")
}

var entries: [Entry] = []
for case let file as URL in enumerator {
    let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard attributes.isSymbolicLink != true else { fatalError("SDK inventory rejects symlinks") }
    guard attributes.isRegularFile == true else { continue }
    let canonicalFile = file.standardizedFileURL.resolvingSymlinksInPath().path
    guard canonicalFile.hasPrefix(root.path + "/") else { fatalError("SDK inventory escaped its framework root") }
    let path = String(canonicalFile.dropFirst(root.path.count + 1))
    let handle = try FileHandle(forReadingFrom: file)
    var hash = SHA256(), count: UInt64 = 0
    do {
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data); count += UInt64(data.count)
        }
        try handle.close()
    } catch { try? handle.close(); throw error }
    entries.append(Entry(path: path, bytes: count, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined()))
}

guard !entries.isEmpty, entries.contains(where: { $0.path == "Info.plist" }) else { fatalError(
    "Empty/invalid XCFramework"
) }
entries.sort { $0.path < $1.path }
let canonical = entries.map { "\($0.path):\($0.bytes):\($0.sha256)\n" }.joined()
let inventory = Inventory(
    schemaVersion: 1,
    files: entries,
    contentSHA256: SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
)
if arguments.count == 3 {
    let expected = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
    guard inventory == expected else { fatalError(
        "SDK content does not match the selected inventory; review provenance before replacing the baseline"
    ) }
    print("SDK file inventory verified (\(entries.count) files, \(inventory.contentSHA256)).")
} else {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(inventory)); print("")
}
