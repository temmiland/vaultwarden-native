import Foundation

/// Validated public build configuration. Bundle lookup and live container resolution belong to
/// app/extension composition, not Data or this value. No guessed Team ID/access group is allowed.
public struct AppStorageConfiguration: Sendable, Equatable {
    public let bundleIdentifierPrefix: String
    public let appGroupIdentifier: String
    public let sharedKeychainService: String
    public let privateKeychainService: String
    public let appIdentifierPrefix: String
    public var sharedKeychainAccessGroup: String { appIdentifierPrefix + sharedKeychainService }

    public init(info: [String: String], bundleIdentifier: String?) throws {
        func identifier(_ key: String) throws -> String {
            guard let value = info[key], Self.isIdentifier(value) else {
                throw AppStorageConfigurationError.invalidValue(key: key)
            }
            return value
        }
        bundleIdentifierPrefix = try identifier("VWBundleIdentifierPrefix")
        appGroupIdentifier = try identifier("VWAppGroupIdentifier")
        guard appGroupIdentifier.hasPrefix("group.") else {
            throw AppStorageConfigurationError.invalidValue(key: "VWAppGroupIdentifier")
        }
        sharedKeychainService = try identifier("VWSharedKeychainService")
        privateKeychainService = try identifier("VWPrivateKeychainService")
        guard sharedKeychainService != privateKeychainService else {
            throw AppStorageConfigurationError.invalidValue(key: "VWPrivateKeychainService")
        }
        guard let rawPrefix = info["VWAppIdentifierPrefix"], rawPrefix.hasSuffix(".") else {
            throw AppStorageConfigurationError.invalidValue(key: "VWAppIdentifierPrefix")
        }
        let prefix = String(rawPrefix.dropLast())
        guard prefix.utf8.count == 10,
              prefix.utf8.allSatisfy({ (65 ... 90).contains($0) || (48 ... 57).contains($0) }) else {
            throw AppStorageConfigurationError.invalidValue(key: "VWAppIdentifierPrefix")
        }
        appIdentifierPrefix = prefix + "."
        guard let bundleIdentifier, Self.isIdentifier(bundleIdentifier),
              bundleIdentifier == bundleIdentifierPrefix || bundleIdentifier.hasPrefix(bundleIdentifierPrefix + ".") else {
            throw AppStorageConfigurationError.invalidValue(key: "CFBundleIdentifier")
        }
    }

    /// Resolve only after validating every public setting. Missing entitlements/container deny
    /// startup before composition constructs any private/shared credential stores.
    public func resolveContainer(using resolver: (String) -> URL?) throws -> URL {
        guard let url = resolver(appGroupIdentifier), url.isFileURL else {
            throw AppStorageConfigurationError.sharedContainerUnavailable
        }
        return url
    }

    private static func isIdentifier(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.first != "-" && label.last != "-" && label.utf8.allSatisfy {
                (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 45
            }
        }
    }
}

/// Descriptions include only a known configuration key, never its value or a container path.
public enum AppStorageConfigurationError: Error, LocalizedError, Equatable, Sendable {
    case invalidValue(key: String)
    case sharedContainerUnavailable

    public var errorDescription: String? {
        switch self {
        case let .invalidValue(key):
            return "Missing or invalid \(key). Check Configuration/Local.xcconfig and regenerate the Xcode project."
        case .sharedContainerUnavailable:
            return "The configured App Group container is unavailable. Check signing, App Group registration and entitlements."
        }
    }
}
