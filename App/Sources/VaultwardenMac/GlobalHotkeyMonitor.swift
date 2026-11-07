import AppKit
import ApplicationServices

/// System-wide ⌥⌘V brings Vaultwarden to the front from anywhere. AppKit requires Accessibility
/// trust for a global key monitor; the local monitor still covers the focused-app case.
@MainActor
final class GlobalHotkeyMonitor {
    private var globalMonitor: EventMonitorRegistration?
    private var localMonitor: EventMonitorRegistration?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        start()
    }

    private func start() {
        let localToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if isHotkey(event) {
                action()
                return nil // swallow the keystroke so it doesn't also reach whatever's focused
            }
            return event
        }
        localMonitor = localToken.map(EventMonitorRegistration.init)
        refreshGlobalMonitor()
    }

    @discardableResult
    func refreshGlobalMonitor() -> Bool {
        globalMonitor?.remove()
        globalMonitor = nil
        guard AXIsProcessTrusted() else { return false }
        let globalToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        globalMonitor = globalToken.map(EventMonitorRegistration.init)
        return globalMonitor != nil
    }

    private func handle(_ event: NSEvent) {
        if isHotkey(event) {
            action()
        }
    }

    /// ⌥⌘V - chosen to avoid colliding with any common system/browser shortcut.
    private func isHotkey(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.option, .command]
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    deinit {
        // deinit is nonisolated in Swift 5. Transfer only actor-isolated registration wrappers,
        // never opaque non-Sendable AppKit tokens, and remove them on the main actor.
        Task { @MainActor [globalMonitor, localMonitor] in
            globalMonitor?.remove()
            localMonitor?.remove()
        }
    }
}

/// The opaque AppKit token never leaves MainActor; the wrapper is safe to capture for cleanup.
@MainActor
private final class EventMonitorRegistration {
    private var token: Any?
    init(_ token: Any) { self.token = token }
    func remove() {
        guard let token else { return }
        self.token = nil
        NSEvent.removeMonitor(token)
    }
}
