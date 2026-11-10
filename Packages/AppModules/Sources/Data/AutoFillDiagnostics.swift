import Foundation

/// Last result per fixed AutoFill stage, kept only in this app's local cache. No account, path,
/// error description/userInfo, credential descriptor, token, key or vault data is recorded.
public enum AutoFillDiagnostics {
    public enum Stage: String, Sendable {
        case unlockPublication, cache, identities, clockProbe, cacheProbe, containerPermissionsProbe
    }

    struct Failure: Codable, Sendable {
        let category: String
        let code: Int
        let underlyingCategory: String?
        let underlyingCode: Int?

        init(_ error: Error) {
            let value = error as NSError
            category = Self.category(error)
            code = value.code
            let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError
            underlyingCategory = underlying.map(Self.category)
            underlyingCode = underlying?.code
        }

        private static func category(_ error: Error) -> String {
            switch (error as NSError).domain {
            case NSCocoaErrorDomain: return "Cocoa"
            case NSPOSIXErrorDomain: return "POSIX"
            case NSOSStatusErrorDomain: return "OSStatus"
            case NSURLErrorDomain: return "URL"
            default: return String(reflecting: type(of: error))
            }
        }
    }

    private struct Entry: Codable {
        let succeeded: Bool
        let failure: Failure?
    }

    public static func record(_ stage: Stage, error: Error? = nil) {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "VWBundleIdentifierPrefix") as? String,
              let identifier = Bundle.main.bundleIdentifier,
              identifier == prefix || identifier.hasPrefix(prefix + "."),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let directory = caches.appendingPathComponent(identifier + ".diagnostics", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            let entry = Entry(succeeded: error == nil, failure: error.map(Failure.init))
            try JSONEncoder().encode(entry).write(
                to: directory.appendingPathComponent(stage.rawValue + ".json"),
                options: [.atomic, .completeFileProtection]
            )
        } catch { /* Diagnostics never change the authorization or cleanup outcome. */ }
    }
}
