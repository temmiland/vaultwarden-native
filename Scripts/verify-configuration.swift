#!/usr/bin/env swift
import Foundation

// Run from the repository root after XcodeGen. No signing, registration or credential access.
// Optional NAME=value arguments override only public contributor configuration for fixture checks.
struct ConfigurationCheckFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw ConfigurationCheckFailure(description: message) }
}

let targetFiles: [String: (suffix: String, info: String, entitlements: String)] = [
    "VaultwardenMac": ("", "App/VaultwardenMac-Info.plist", "App/VaultwardenMac.entitlements"),
    "VaultwardenIOS": (".ios", "App/VaultwardenIOS-Info.plist", "App/VaultwardenIOS.entitlements"),
    "VaultwardenAutoFill": (
        ".autofill",
        "AutoFillExtension/VaultwardenAutoFill-Info.plist",
        "AutoFillExtension/VaultwardenAutoFill.entitlements"
    ),
    "VaultwardenIOSAutoFill": (
        ".ios.autofill",
        "AutoFillExtension/VaultwardenIOSAutoFill-Info.plist",
        "AutoFillExtension/VaultwardenIOSAutoFill.entitlements"
    ),
]
let integrationTargets: Set = ["VaultwardenMacIntegrationTests", "VaultwardenIOSIntegrationTests"]
let runtimeSettings = [
    "VWBundleIdentifierPrefix": "VW_BUNDLE_ID_PREFIX",
    "VWAppGroupIdentifier": "VW_APP_GROUP_IDENTIFIER",
    "VWSharedKeychainService": "VW_SHARED_KEYCHAIN_SERVICE",
    "VWPrivateKeychainService": "VW_PRIVATE_KEYCHAIN_SERVICE",
    "VWAppIdentifierPrefix": "VW_KEYCHAIN_PREFIX",
    "CFBundleShortVersionString": "MARKETING_VERSION",
    "CFBundleVersion": "CURRENT_PROJECT_VERSION",
]

func readPlist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw ConfigurationCheckFailure(description: "Invalid plist: \(path)")
    }
    return result
}

func requiredSetting(_ key: String, in settings: [String: String], context: String) throws -> String {
    guard let value = settings[key], !value.isEmpty, !value.contains("$("), !value.contains("${") else {
        throw ConfigurationCheckFailure(description: "\(context): unexpanded or empty \(key).")
    }
    return value
}

func buildSettings(configuration: String, overrides: [String]) throws -> [[String: Any]] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
    process.arguments = ["-project", "Vaultwarden.xcodeproj", "-alltargets", "-configuration", configuration,
                         "-showBuildSettings", "-json", "CODE_SIGNING_ALLOWED=NO"] + overrides
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.standardError
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "xcodebuild could not read \(configuration) settings.")
    guard let settings = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw ConfigurationCheckFailure(description: "Unexpected xcodebuild settings format.")
    }
    return settings
}

do {
    let overrides = Array(CommandLine.arguments.dropFirst())
    let allowed = Set(["DEVELOPMENT_TEAM", "VW_BUNDLE_ID_PREFIX", "VW_APP_GROUP_IDENTIFIER",
                       "VW_SHARED_KEYCHAIN_SERVICE", "VW_PRIVATE_KEYCHAIN_SERVICE", "VW_KEYCHAIN_PREFIX"])
    for argument in overrides {
        let pieces = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        try require(
            pieces.count == 2 && allowed.contains(String(pieces[0])),
            "Arguments must be public signing/identifier NAME=value overrides."
        )
    }
    for configuration in ["Debug", "Release"] {
        let rows = try buildSettings(configuration: configuration, overrides: overrides)
        var checked = Set<String>()
        var checkedIntegration = Set<String>()
        var referenceStorage: [String]?
        for row in rows {
            // Synthetic integration bundles must stay hostless and unentitled: no App Group,
            // shared Keychain or app process may leak owner storage into composition tests.
            if let target = row["target"] as? String, integrationTargets.contains(target) {
                let settings = row["buildSettings"] as? [String: String] ?? [:]
                try require(
                    (settings["CODE_SIGN_ENTITLEMENTS"] ?? "").isEmpty && (settings["TEST_HOST"] ?? "").isEmpty
                        && (settings["BUNDLE_LOADER"] ?? "").isEmpty,
                    "\(configuration)/\(target): integration bundles must be hostless and carry no entitlements."
                )
                checkedIntegration.insert(target)
                continue
            }
            guard let target = row["target"] as? String, let files = targetFiles[target] else { continue }
            guard let settings = row["buildSettings"] as? [String: String] else {
                throw ConfigurationCheckFailure(description: "Missing settings for \(target).")
            }
            let prefix = settings["VW_KEYCHAIN_PREFIX"] ?? ""
            try require(
                prefix.range(of: "^[A-Z0-9]{10}\\.$", options: .regularExpression) != nil,
                "\(configuration)/\(target): missing or invalid signing prefix. Set DEVELOPMENT_TEAM in Configuration/Local.xcconfig; an explicit VW_KEYCHAIN_PREFIX must end in a dot."
            )
            let context = "\(configuration)/\(target)"
            for key in runtimeSettings.values { _ = try requiredSetting(key, in: settings, context: context) }
            let bundlePrefix = try requiredSetting("VW_BUNDLE_ID_PREFIX", in: settings, context: context)
            try require(
                settings["PRODUCT_BUNDLE_IDENTIFIER"] == bundlePrefix + files.suffix,
                "\(configuration)/\(target): bundle identifier does not match the configured family."
            )
            let appGroup = try requiredSetting("VW_APP_GROUP_IDENTIFIER", in: settings, context: context)
            try require(
                appGroup.hasPrefix("group."),
                "\(configuration)/\(target): App Group must start with group."
            )
            try require(
                settings["VW_SHARED_KEYCHAIN_SERVICE"] != settings["VW_PRIVATE_KEYCHAIN_SERVICE"],
                "\(configuration)/\(target): private/shared Keychain namespaces must differ."
            )
            let storage = try ["VW_BUNDLE_ID_PREFIX", "VW_APP_GROUP_IDENTIFIER", "VW_SHARED_KEYCHAIN_SERVICE",
                               "VW_PRIVATE_KEYCHAIN_SERVICE", "VW_KEYCHAIN_PREFIX"].map {
                try requiredSetting($0, in: settings, context: context)
            }
            if let referenceStorage {
                try require(
                    storage == referenceStorage,
                    "\(configuration): app/extension storage configuration differs."
                )
            } else { referenceStorage = storage }
            let info = try readPlist(files.info)
            for (key, setting) in runtimeSettings {
                try require(
                    info[key] as? String == "$(\(setting))",
                    "\(target): \(key) must expand from \(setting), not a hardcoded value."
                )
            }
            let entitlements = try readPlist(files.entitlements)
            try require(
                entitlements["com.apple.security.application-groups"] as? [String] == ["$(VW_APP_GROUP_IDENTIFIER)"],
                "\(target): App Group entitlement does not use the runtime setting."
            )
            try require(
                entitlements["keychain-access-groups"] as? [String] == [
                    "$(VW_KEYCHAIN_PREFIX)$(VW_SHARED_KEYCHAIN_SERVICE)",
                ],
                "\(target): Keychain entitlement does not use the runtime settings."
            )
            let conditions = (settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] ?? "").split(
                whereSeparator: \.isWhitespace
            )
            try require(
                conditions.contains("DEBUG") == (configuration == "Debug"),
                "\(configuration)/\(target): DEBUG condition does not match the build configuration."
            )
            checked.insert(target)
        }
        try require(checked == Set(targetFiles.keys), "\(configuration): did not verify all four app/extension targets.")
        try require(checkedIntegration == integrationTargets, "\(configuration): integration bundles are missing.")
        print("\(configuration): all four targets use matching, expanded storage settings and entitlement templates.")
    }
    print("Configuration checks passed. This does not verify provisioning or signed-device entitlements.")
} catch {
    FileHandle.standardError.write(Data("Configuration check failed: \(error)\n".utf8))
    exit(1)
}
