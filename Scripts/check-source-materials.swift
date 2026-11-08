import CryptoKit
import Foundation

struct Material: Decodable {
    let path: String
    let bytes: Int
    let sha256: String
}

struct SourceInventory: Decodable {
    let schemaVersion: Int
    let files: [Material]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Source publication check: \(message)\n".utf8))
    exit(1)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || (arguments.count == 2 && arguments[0] == "--manifest") else {
    fail("usage: swift Scripts/check-source-materials.swift [--manifest FILE]")
}

let manifestURL = arguments.isEmpty
    ? root.appendingPathComponent("Docs/ThirdParty/SourceMaterialInventory.json")
    : URL(fileURLWithPath: arguments[1])
let inventory = try JSONDecoder().decode(SourceInventory.self, from: Data(contentsOf: manifestURL))
guard inventory.schemaVersion == 1 else { fail("unknown material inventory schema") }

func gitFiles(_ options: [String]) throws -> Set<String> {
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.currentDirectoryURL = root
    process.arguments = ["ls-files", "-z"] + options
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("cannot enumerate source files") }
    return Set(String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init))
}

let tracked = try gitFiles(["--cached"])
let forbiddenPrefixes = [".build/", "DerivedData/", "sdk-internal/", "Packages/VaultwardenSDK/Frameworks/"]
for path in tracked {
    if ["CLAUDE_HANDOFF.md", "Configuration/Local.xcconfig"].contains(path)
        || forbiddenPrefixes.contains(where: { path.hasPrefix($0) })
        || path.contains(".xcodeproj/")
        || ["p12", "p8", "mobileprovision", "key"].contains(URL(fileURLWithPath: path).pathExtension) {
        fail("private/generated distribution material is tracked: \(path)")
    }
}

let files = try gitFiles(["--cached", "--others", "--exclude-standard"])
let materialPaths = Set(files.filter {
    $0.hasPrefix("Packages/VaultwardenSDK/Sources/")
        || $0 == "App/Resources/Artwork/vaultwarden-icon.svg"
        || ($0.hasPrefix("App/Resources/Assets.xcassets/AppIcon.appiconset/") && $0.hasSuffix(".png"))
        || ($0.hasPrefix("Docs/ThirdParty/") && $0.hasSuffix(".txt"))
        || $0 == "Packages/AppModules/Sources/AutoFillData/Resources/public_suffix_list.dat"
        || ($0.hasPrefix("Scripts/patches/") && $0.hasSuffix(".patch"))
})
guard Set(inventory.files.map(\.path)) == materialPaths,
      inventory.files.count == materialPaths.count else { fail("third-party material set changed; review the inventory") }
for material in inventory.files {
    let url = root.appendingPathComponent(material.path)
    let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
        fail("expected a regular third-party source file: \(material.path)")
    }
    let data = try Data(contentsOf: url)
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard data.count == material.bytes, hash == material.sha256 else {
        fail("third-party source bytes changed: \(material.path)")
    }
}

print(
    "Source material inventory verified (\(inventory.files.count) files); private/generated artifacts absent from tracked source. License approval remains separate."
)
