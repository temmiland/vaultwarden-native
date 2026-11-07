import SwiftUI

@main
@MainActor
struct VaultwardenIOSApp: App {
    @State private var startup = AppStartup.load()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppStartupRootView(startup: startup)
                .privacyShield(isActive: scenePhase != .active)
        }
    }
}

/// Covers the UI whenever the app isn't frontmost.
///
/// iOS snapshots the window for the app switcher at exactly that moment, and the snapshot is
/// written to disk. Without this, the user's vault list - names, usernames, and whatever detail
/// screen was open - ends up in a cached image outside the app's control.
private struct PrivacyShield: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
    }
}

extension View {
    func privacyShield(isActive: Bool) -> some View {
        modifier(PrivacyShield(isActive: isActive))
    }
}
