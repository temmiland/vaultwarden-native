import Data
import Foundation
import SecurityStorage

/// Explicit developer launch option. Exercises only an owned synthetic file and the live clock
/// anchor, before login, and records only success/error codes in the app's private cache.
enum AppStorageProbe {
    static func runIfRequested(containerURL: URL) {
        guard ProcessInfo.processInfo.environment["VW_STORAGE_PROBE"] == "1" else { return }
        do {
            _ = try SharedClockSession.currentID(containerURL: containerURL)
            AutoFillDiagnostics.record(.clockProbe)
        } catch { AutoFillDiagnostics.record(.clockProbe, error: error) }
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: containerURL.path
            )
            AutoFillDiagnostics.record(.containerPermissionsProbe)
        } catch { AutoFillDiagnostics.record(.containerPermissionsProbe, error: error) }
        let files = AtomicAutoFillProjectionFileStore(
            directoryURL: containerURL, fileName: ".storage-probe-\(UUID().uuidString).tmp"
        )
        defer { try? files.removeProjection() }
        do {
            try files.replaceProjectionAtomically(with: Foundation.Data("synthetic-storage-probe".utf8))
            AutoFillDiagnostics.record(.cacheProbe)
        } catch { AutoFillDiagnostics.record(.cacheProbe, error: error) }
    }
}
