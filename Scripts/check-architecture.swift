import Foundation

// Repository-owned source check, independent of the generated SDK binary. Run from repository
// root; optional --root accepts only an explicitly provided fixture checkout for negative tests.
struct ArchitectureViolation: Error { let message: String }
let arguments = Array(CommandLine.arguments.dropFirst())
let root: URL
if arguments.isEmpty {
    root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
} else if arguments.count == 2, arguments[0] == "--root" {
    root = URL(fileURLWithPath: arguments[1], isDirectory: true)
} else {
    fatalError("Usage: swift Scripts/check-architecture.swift [--root PATH]")
}

let sourceRoot = root.appendingPathComponent("Packages/AppModules/Sources").standardizedFileURL.resolvingSymlinksInPath()
let presentation = ["AuthFeature", "VaultFeature", "SendFeature", "SettingsFeature", "SharedUI", "AppFeature",
                    "AutoFillFeature",
                    "AuthPresentation", "VaultPresentation", "SendPresentation", "SettingsPresentation"]
let forbiddenUI = Set(
    [
        "BitwardenSdk",
        "BitwardenSDKAdapter",
        "Data",
        "AutoFillData",
        "Networking",
        "SecurityStorage",
        "PlatformServices",
        "AppKit",
        "UIKit",
        "Security",
        "LocalAuthentication",
    ]
)
let importPattern = try NSRegularExpression(
    pattern: #"^\s*(?:(?:@testable|@_exported|@preconcurrency)\s+)?import\s+(?:(?:class|struct|enum|protocol|func|var|let|typealias)\s+)?([A-Za-z_][A-Za-z_0-9]*)"#,
    options: .anchorsMatchLines
)
var violations: [String] = [], files = 0
guard let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
    fatalError("Missing AppModules source tree")
}

for case let url as URL in enumerator where url.pathExtension == "swift" {
    files += 1
    let relative = String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(sourceRoot.path.count + 1))
    let target = relative.split(separator: "/").first.map(String.init) ?? ""
    let source = try String(contentsOf: url, encoding: .utf8)
    for match in importPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
        guard let range = Range(match.range(at: 1), in: source) else { continue }
        let module = String(source[range])
        if presentation.contains(target), forbiddenUI.contains(module) {
            violations.append("\(relative): forbidden presentation import \(module)")
        }
        if module == "BitwardenSdk", target != "BitwardenSDKAdapter" {
            violations.append("\(relative): raw SDK import outside BitwardenSDKAdapter")
        }
        if target == "Domain", module != "Foundation" {
            violations.append("\(relative): Domain import \(module)")
        }
        if ["Networking", "SecurityStorage", "AutoFillContract"].contains(target),
           ["Data", "BitwardenSdk", "BitwardenSDKAdapter"].contains(module) || presentation.contains(module) {
            violations.append("\(relative): low-level target has reverse import \(module)")
        }
    }
    if source.range(of: #"\.live\s*\("#, options: .regularExpression) != nil {
        violations.append("\(relative): live factory outside composition roots")
    }
    if target != "Networking", source.range(of: #"URLSessionHTTPClient\s*\("#, options: .regularExpression) != nil {
        violations.append("\(relative): concrete HTTP transport outside composition/networking")
    }
}

guard files > 0 else { fatalError("Empty AppModules source tree") }
// Manifest rules stop a dependency being added even when no file imports it yet.
let manifest = try String(contentsOf: root.appendingPathComponent("Packages/AppModules/Package.swift"), encoding: .utf8)
for target in ["AuthPresentation", "VaultPresentation", "SendPresentation", "SettingsPresentation", "AutoFillFeature"] {
    let pattern = #"\.target\(\s*name:\s*""# + target + #"",\s*dependencies:\s*\[([^\]]*)\]"#
    let expression = try NSRegularExpression(pattern: pattern)
    guard let match = expression.firstMatch(in: manifest, range: NSRange(manifest.startIndex..., in: manifest)),
          let range = Range(match.range(at: 1), in: manifest) else {
        violations.append("Missing/checker-incompatible declaration for \(target)"); continue
    }
    let dependencies = manifest[range].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
        of: "\"",
        with: ""
    ) }
    let allowed = target == "AutoFillFeature" ? ["Domain", "SharedUI", "AutoFillContract"] : ["Domain", "SharedUI"]
    if !dependencies.allSatisfy({ allowed.contains($0) }) {
        violations.append("\(target): dependencies must be \(allowed.joined(separator: "/")) only")
    }
}

if !violations.isEmpty {
    for message in violations.sorted() { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    exit(1)
}

print("Architecture checks passed (\(files) project-owned Swift source files).")
