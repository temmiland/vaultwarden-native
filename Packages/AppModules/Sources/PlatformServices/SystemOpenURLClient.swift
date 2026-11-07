import Domain
import Foundation

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Opens a URL through the active platform and reports failure to the caller so UI can present a
/// recovery message instead of silently dropping the action.
@MainActor
public final class SystemOpenURLClient: OpenURLClient {
    public init() {}

    public func open(_ url: URL) async throws {
        #if os(iOS)
            let didOpen = await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
        #else
            let didOpen = NSWorkspace.shared.open(url)
        #endif

        guard didOpen else { throw OpenURLClientError.unableToOpen }
    }
}
