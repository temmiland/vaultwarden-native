import Domain
import SwiftUI

/// Entry point for the Auth feature. Owns server setup, login, two-factor, vault unlock (password
/// and Touch ID), and logout. Everything else in this package is an internal implementation detail
/// reached only through this view - see `AuthCoordinator` for the navigation graph.
///
/// `onAuthenticated` transfers one opaque Domain runtime capability to the app owner.
///
/// `onSessionExpired` fires if the server later stops accepting the refresh token (it expired, or
/// the device was revoked server-side). The app should drop its session in response - the user is
/// no longer signed in, whatever the UI currently shows.
public struct AuthRootView: View {
    @State private var coordinator: AuthCoordinator
    @State private var hasStarted = false

    public init(
        commands: any AuthFlowCommands,
        biometricClient: any BiometricClient,
        onLogout: @escaping () async -> Void,
        onAuthenticated: @escaping (any AuthenticatedSessionCapability) -> Void,
        onSessionExpired: @escaping @MainActor @Sendable (UUID) -> Void = { _ in }
    ) {
        _coordinator = State(initialValue: AuthCoordinator(
            commands: commands,
            biometricClient: biometricClient,
            onLogout: onLogout,
            onAuthenticated: onAuthenticated,
            onSessionExpired: onSessionExpired
        ))
    }

    public var body: some View {
        AuthFlowView(coordinator: coordinator)
            .alert(
                "Keychain operation failed",
                isPresented: Binding(
                    get: { coordinator.keychainErrorMessage != nil },
                    set: { if !$0 { coordinator.dismissKeychainError() } }
                )
            ) {
                Button("OK", role: .cancel) { coordinator.dismissKeychainError() }
            } message: {
                Text(coordinator.keychainErrorMessage ?? "Your saved session remains available.")
            }
            .onAppear {
                // `onAppear` fires again whenever this view is re-inserted (tab switches, window
                // restoration). Restarting would throw away an in-progress login and bounce the
                // user back to the unlock/server-setup screen.
                guard !hasStarted else { return }
                hasStarted = true
                coordinator.start()
            }
            .onDisappear {
                coordinator.stop()
                hasStarted = false
            }
    }
}
