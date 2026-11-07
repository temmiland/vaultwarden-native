import Domain
import Foundation

#if os(iOS)
    import UIKit
    import UniformTypeIdentifiers
#else
    import AppKit
#endif

/// Narrow, main-actor-only seam around the system pasteboard. It lets the expiry policy be tested
/// without accessing a user's real clipboard and prevents feature code from importing AppKit or
/// UIKit.
@MainActor
protocol SecretPasteboardWriting: AnyObject {
    var changeCount: Int { get }

    /// Writes a secret with the platform's strongest available privacy attributes and returns the
    /// change count *after* the write.
    @discardableResult
    func writeSecret(_ value: String, expiresAfter: TimeInterval) -> Int

    @discardableResult
    func clearContents() -> Int
}

#if os(iOS)
    @MainActor
    private final class SystemSecretPasteboard: SecretPasteboardWriting {
        private let pasteboard: UIPasteboard

        init(pasteboard: UIPasteboard = .general) {
            self.pasteboard = pasteboard
        }

        var changeCount: Int { pasteboard.changeCount }

        func writeSecret(_ value: String, expiresAfter: TimeInterval) -> Int {
            // `localOnly` keeps passwords out of Universal Clipboard. The operating-system expiry is
            // intentionally paired with the in-process change-count guarded cleanup below: it still
            // applies if the app is terminated before its scheduled task gets a chance to run.
            let expiryDate = Date().addingTimeInterval(max(0, expiresAfter))
            pasteboard.setItems(
                [[UTType.utf8PlainText.identifier: value]],
                options: [.localOnly: true, .expirationDate: expiryDate]
            )
            return pasteboard.changeCount
        }

        func clearContents() -> Int {
            pasteboard.items = []
            return pasteboard.changeCount
        }
    }
#else
    @MainActor
    private final class SystemSecretPasteboard: SecretPasteboardWriting {
        /// De-facto standard type respected by clipboard managers. Writing it alongside the plain
        /// string asks history managers not to retain a copied password or Send link.
        private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

        private let pasteboard: NSPasteboard

        init(pasteboard: NSPasteboard = .general) {
            self.pasteboard = pasteboard
        }

        var changeCount: Int { pasteboard.changeCount }

        func writeSecret(_ value: String, expiresAfter _: TimeInterval) -> Int {
            // macOS has no pasteboard-level expiry. ClipboardAutoClearService schedules the guarded
            // cleanup, while the concealed type protects against compliant history managers.
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            pasteboard.setString(value, forType: Self.concealedType)
            return pasteboard.changeCount
        }

        func clearContents() -> Int {
            pasteboard.clearContents()
            return pasteboard.changeCount
        }
    }
#endif

/// Production `PasteboardClient`. Each copy records the system change count and clears only when
/// it remains unchanged at expiry, so delayed cleanup cannot erase content copied by another app.
@MainActor
public final class ClipboardAutoClearService: PasteboardClient {
    /// The default is deliberately conservative and remains an implementation detail of this
    /// adapter; features only request a secure copy and do not control clipboard retention.
    nonisolated public static let defaultClearDelay: TimeInterval = 45

    typealias Scheduler = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    private let pasteboard: SecretPasteboardWriting
    private let scheduler: Scheduler

    public convenience init() {
        self.init(pasteboard: SystemSecretPasteboard())
    }

    init(
        pasteboard: SecretPasteboardWriting,
        scheduler: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in work() }
            }
        }
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler
    }

    public func copySecret(_ value: String) {
        copySecret(value, clearAfter: Self.defaultClearDelay)
    }

    func copySecret(_ value: String, clearAfter: TimeInterval) {
        let sanitizedDelay = max(0, clearAfter)
        let changeCountAfterCopy = pasteboard.writeSecret(value, expiresAfter: sanitizedDelay)

        let pasteboard = pasteboard
        scheduler(sanitizedDelay) {
            guard pasteboard.changeCount == changeCountAfterCopy else {
                // The user or another app copied something since our write. Preserve it.
                return
            }
            pasteboard.clearContents()
        }
    }
}
