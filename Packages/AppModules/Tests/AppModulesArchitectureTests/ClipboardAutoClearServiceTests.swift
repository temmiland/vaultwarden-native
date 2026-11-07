import Foundation
@testable import PlatformServices
import Testing

@Suite
@MainActor
struct ClipboardAutoClearServiceTests {
    @Test(arguments: [false, true])
    func scheduledCleanupSurvivesServiceReleaseAndPreservesLaterCopies(replaced: Bool) {
        let pasteboard = MockSecretPasteboard()
        var work: (@MainActor @Sendable () -> Void)?
        weak var released: ClipboardAutoClearService?
        do {
            let service = ClipboardAutoClearService(
                pasteboard: pasteboard,
                scheduler: { _, callback in work = callback }
            )
            released = service
            service.copySecret("secret")
        }
        #expect(released == nil)
        if replaced { pasteboard.simulateExternalCopy("new content") }
        work?()
        #expect(pasteboard.contents == (replaced ? "new content" : nil))
    }

    @Test
    func copyWritesASecretAndSchedulesAnExpiry() {
        let pasteboard = MockSecretPasteboard()
        var scheduledDelay: TimeInterval?
        let service = ClipboardAutoClearService(pasteboard: pasteboard, scheduler: { delay, _ in
            scheduledDelay = delay
        })

        service.copySecret("secret-password", clearAfter: 30)

        #expect(pasteboard.contents == "secret-password")
        #expect(pasteboard.lastExpiry == 30)
        #expect(scheduledDelay == 30)
    }

    @Test
    func expiryClearsOnlyWhenThePasteboardStillContainsOurCopy() {
        let pasteboard = MockSecretPasteboard()
        var scheduledWork: (() -> Void)?
        let service = ClipboardAutoClearService(pasteboard: pasteboard, scheduler: { _, work in
            scheduledWork = work
        })

        service.copySecret("secret-password", clearAfter: 30)
        scheduledWork?()

        #expect(pasteboard.contents == nil)
    }

    @Test
    func expiryDoesNotEraseContentCopiedAfterOurSecret() {
        let pasteboard = MockSecretPasteboard()
        var scheduledWork: (() -> Void)?
        let service = ClipboardAutoClearService(pasteboard: pasteboard, scheduler: { _, work in
            scheduledWork = work
        })

        service.copySecret("secret-password", clearAfter: 30)
        pasteboard.simulateExternalCopy("user-content")
        scheduledWork?()

        #expect(pasteboard.contents == "user-content")
    }

    @Test
    func negativeExpiryIsClampedToImmediateCleanup() {
        let pasteboard = MockSecretPasteboard()
        var scheduledDelay: TimeInterval?
        let service = ClipboardAutoClearService(pasteboard: pasteboard, scheduler: { delay, _ in
            scheduledDelay = delay
        })

        service.copySecret("secret-password", clearAfter: -1)

        #expect(pasteboard.lastExpiry == 0)
        #expect(scheduledDelay == 0)
    }

    @Test
    func staleExpiryCannotClearASecretCopiedLater() {
        let pasteboard = MockSecretPasteboard()
        var scheduledWork: [@MainActor @Sendable () -> Void] = []
        let service = ClipboardAutoClearService(pasteboard: pasteboard, scheduler: { _, work in
            scheduledWork.append(work)
        })

        service.copySecret("first")
        service.copySecret("second")
        scheduledWork[0]()

        #expect(pasteboard.contents == "second")
        scheduledWork[1]()
        #expect(pasteboard.contents == nil)
    }
}

@MainActor
private final class MockSecretPasteboard: SecretPasteboardWriting {
    private(set) var contents: String?
    private(set) var lastExpiry: TimeInterval?
    private(set) var changeCount = 0

    func writeSecret(_ value: String, expiresAfter: TimeInterval) -> Int {
        contents = value
        lastExpiry = expiresAfter
        changeCount += 1
        return changeCount
    }

    func clearContents() -> Int {
        contents = nil
        changeCount += 1
        return changeCount
    }

    func simulateExternalCopy(_ value: String) {
        contents = value
        changeCount += 1
    }
}
