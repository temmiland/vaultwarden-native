import AppKit
import ApplicationServices
import PlatformServices
import SettingsPresentation
import SwiftUI

/// `swift run`-launched executables have no `.app` bundle, so AppKit never activates them as the
/// foreground app on their own — the window shows up but never becomes key and can't receive
/// keyboard input until something explicitly activates it. This is that explicit activation.
/// Also owns the global hotkey monitor for the lifetime of the app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyMonitor: GlobalHotkeyMonitor?
    @MainActor static var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Self.bringToFront()
        hotkeyMonitor = GlobalHotkeyMonitor { Self.bringToFront() }
    }

    @MainActor
    func refreshQuickAccessHotkey() -> Bool { hotkeyMonitor?.refreshGlobalMonitor() ?? false }

    @MainActor
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let openMainWindow { openMainWindow() }
        else { (NSApp.windows.first { $0.canBecomeKey })?.makeKeyAndOrderFront(nil) }
    }
}

@main
@MainActor
struct VaultwardenMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var startup = AppStartup.load()

    var body: some Scene {
        Window("Vaultwarden", id: "main") {
            MainWindowContent(startup: startup)
        }
        // `.contentSize` pinned the window to its content's ideal size, which for a three-column
        // vault browser meant it couldn't usefully be resized. `.contentMinSize` keeps the floor
        // (set above) while letting the user make the window as large as they like.
        .windowResizability(.contentMinSize)

        MenuBarExtra("Vaultwarden", systemImage: "lock.fill") {
            MenuBarContentView(appModel: startup.model)
        }

        Settings {
            SettingsSceneView(startup: startup)
        }
    }
}

private struct MainWindowContent: View {
    let startup: AppStartup
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        AppStartupRootView(startup: startup)
            .frame(minWidth: 720, minHeight: 460)
            .onAppear {
                let open = openWindow
                AppDelegate.openMainWindow = { open(id: "main") }
            }
    }
}

/// Quick access from the menu bar - always present, independent of whether the main window is
/// open, per the "unübersichtlich" complaint about the Electron app that started this whole
/// project (that app has no equivalent to this).
private struct MenuBarContentView: View {
    let appModel: VaultwardenAppModel?

    var body: some View {
        Button("Open Vaultwarden") { AppDelegate.bringToFront() }
            .keyboardShortcut("v", modifiers: [.command, .option])
        if let appModel, appModel.session != nil {
            Button("Lock Now") { Task { await appModel.lockNow() } }
        }
        Divider()
        Button("Quit Vaultwarden") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Settings (⌘,) reads the same session store as the main window - shows real settings once
/// logged in, a simple placeholder before that (there's nothing to configure pre-login). "General"
/// is app-shell-level (launch at login, hotkey), so it lives here rather than in `SettingsPresentation`.
private struct SettingsSceneView: View {
    let startup: AppStartup

    var body: some View {
        switch startup {
        case let .unavailable(error):
            AppConfigurationFailureView(error: error)
                .frame(width: 480, height: 420)
        case let .ready(composition, appModel):
            settings(composition: composition, appModel: appModel)
        }
    }

    private func settings(composition: AppComposition, appModel: VaultwardenAppModel) -> some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            if appModel.pendingSecurityAction != nil {
                SessionSecurityRecoveryView(appModel: appModel)
                    .tabItem { Label("Account", systemImage: "lock.fill") }
            } else if let adapter = appModel.session {
                SettingsRootView(
                    account: adapter.account,
                    checkSessionAccess: { try adapter.checkAccess() },
                    sessionStates: { await adapter.session.runtime.sessionStates() },
                    settingsRepository: adapter.settingsRepository,
                    timeoutSettings: composition.timeoutSettings,
                    pinSettings: composition.makePinUnlockSettings(for: adapter.session),
                    openURLClient: SystemOpenURLClient(),
                    onLockNow: { Task { await appModel.lockNow() } },
                    onLogout: { Task { await appModel.logOut() } }
                )
                .id(adapter.id)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            }
        }
        .frame(width: 480, height: 420)
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchAtLoginStatus = LaunchAtLoginService.status
    @State private var launchAtLoginError: String?
    @State private var hasAccessibilityTrust = AXIsProcessTrusted()
    @State private var isQuickAccessHotkeyAvailable = false

    var body: some View {
        Form {
            Toggle(isOn: Binding(
                get: { launchAtLoginStatus == .enabled },
                set: { enabled in setLaunchAtLogin(enabled) }
            )) {
                Text("Launch at Login")
            }
            if launchAtLoginStatus == .requiresApproval {
                Text("Allow Vaultwarden in System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if launchAtLoginStatus == .unavailable {
                Text("Launch at Login is unavailable for this app build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let launchAtLoginError {
                Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
            }

            LabeledContent("Quick Access Hotkey", value: isQuickAccessHotkeyAvailable ? "⌥⌘V" : "Unavailable")
            if !isQuickAccessHotkeyAvailable {
                Text(hasAccessibilityTrust
                    ? "The system-wide key monitor could not be registered. Check Accessibility access and try again."
                    : "System-wide key monitoring needs Accessibility access. Enable Vaultwarden in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check Accessibility Access Again", action: refreshAccessibilityStatus)
            }
        }
        .padding(20)
        .onAppear(perform: refreshStatuses)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatuses() }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do { try LaunchAtLoginService.setEnabled(enabled) }
        catch { launchAtLoginError = "Couldn't update Launch at Login. Check the system Login Items settings." }
        launchAtLoginStatus = LaunchAtLoginService.status
    }

    private func refreshAccessibilityStatus() {
        hasAccessibilityTrust = AXIsProcessTrusted()
        isQuickAccessHotkeyAvailable = (NSApp.delegate as? AppDelegate)?.refreshQuickAccessHotkey() ?? false
    }

    private func refreshStatuses() {
        launchAtLoginStatus = LaunchAtLoginService.status
        refreshAccessibilityStatus()
    }
}
