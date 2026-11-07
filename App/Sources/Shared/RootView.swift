import AuthPresentation
import PlatformServices
import SecurityStorage
import SendPresentation
import SettingsPresentation
import SwiftUI
import VaultPresentation

/// The main window's content: AuthPresentation until a session exists, then the app's tabs.
/// Integration glue only - feature presentation targets are independently tested in AppModules.
struct RootView: View {
    let appModel: VaultwardenAppModel
    let composition: AppComposition

    /// On iOS this is the only way into Settings, so the tab has to exist there. On macOS the
    /// Settings *scene* (⌘,) is the platform-native home for it and a Settings tab in the window
    /// would be redundant.
    private var showsSettingsTab: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    var body: some View {
        Group {
            switch appModel.state {
            case .securityRecovery:
                SessionSecurityRecoveryView(appModel: appModel)
            case .preparingSession:
                ProgressView("Preparing secure session…")
            case let .unlocked(adapter):
                let session = adapter.session
                TabView {
                    VaultRootView(
                        repository: adapter.vaultRepository,
                        generator: session.passwordGeneratorService,
                        checkSessionAccess: { try session.checkAccess() },
                        onLogout: { Task { await appModel.logOut() } },
                        fileImportClient: SystemFileImportClient(),
                        pasteboardClient: session.scopedPasteboardClient(ClipboardAutoClearService()),
                        removeTemporaryFile: { url in
                            try await SensitiveTemporaryFileStore.shared.removeWorkDirectory(containing: url)
                        }
                    )
                    .tabItem { Label("Vault", systemImage: "lock.fill") }

                    SendRootView(
                        repository: adapter.sendRepository,
                        checkSessionAccess: { try adapter.checkAccess() },
                        sessionStates: { await session.runtime.sessionStates() },
                        fileImportClient: SystemFileImportClient(),
                        pasteboardClient: session.scopedPasteboardClient(ClipboardAutoClearService())
                    )
                    .tabItem { Label("Send", systemImage: "paperplane.fill") }

                    if showsSettingsTab {
                        SettingsRootView(
                            account: adapter.account,
                            checkSessionAccess: { try adapter.checkAccess() },
                            sessionStates: { await session.runtime.sessionStates() },
                            settingsRepository: adapter.settingsRepository,
                            timeoutSettings: composition.timeoutSettings,
                            pinSettings: composition.makePinUnlockSettings(for: session),
                            openURLClient: SystemOpenURLClient(),
                            onLockNow: { Task { await appModel.lockNow() } },
                            onLogout: { Task { await appModel.logOut() } }
                        )
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    }
                }
                .id(session.id)
            case .restoring, .signedOut, .locked, .unlocking:
                AuthRootView(
                    commands: composition.authCommands,
                    biometricClient: composition.biometricClient,
                    onLogout: { await appModel.logOut() },
                    onAuthenticated: { session in
                        Task { await composition.accept(session, into: appModel) }
                    },
                    // The refresh token stopped being accepted (expired, or this device was revoked
                    // server-side). Whatever the UI is showing, the user is no longer signed in.
                    onSessionExpired: { id in Task { await appModel.sessionExpired(id) } }
                )
            }
        }
        .task { await appModel.start() }
        .alert(
            "Vault security action failed",
            isPresented: Binding(
                get: { appModel.securityErrorMessage != nil },
                set: { if !$0 { appModel.securityErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appModel.securityErrorMessage = nil }
        } message: {
            Text(appModel.securityErrorMessage ?? "Retry secure cleanup before unlocking again.")
        }
    }
}

/// Recovery is outside the authenticated view tree. Cleanup failure does not reopen an already
/// revoked runtime or silently permit another unlock over remaining shared capabilities.
struct SessionSecurityRecoveryView: View {
    let appModel: VaultwardenAppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.largeTitle)
            Text("Finishing secure cleanup").font(.title2)
            Text("The unlocked session has been revoked. Cleanup must finish before you can unlock again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if appModel.isPerformingSecurityAction {
                ProgressView()
            } else {
                if let error = appModel.securityErrorMessage { Text(error).foregroundStyle(.red) }
                Button("Retry secure cleanup") { Task { await appModel.retrySecurityAction() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
