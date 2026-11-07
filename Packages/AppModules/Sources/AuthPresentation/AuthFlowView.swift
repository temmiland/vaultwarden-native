import SwiftUI

/// Rendering only; the typed controller owns route/model lifetime and injected services.
struct AuthFlowView: View {
    let coordinator: AuthCoordinator

    @ViewBuilder
    var body: some View {
        switch coordinator.screen {
        case let .serverSetup(model): ServerSetupView(model: model)
        case let .login(model): LoginView(model: model)
        case let .twoFactor(model): TwoFactorView(model: model)
        case let .unlock(model): UnlockView(model: model)
        case let .enableBiometrics(model): EnableBiometricsView(model: model)
        case .keychainUnavailable:
            makeKeychainUnavailableView()
        }
    }

    private func makeKeychainUnavailableView() -> some View {
        let id = coordinator.routeID
        return VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
            Text("Saved account unavailable")
                .font(.title2)
            Text("Vaultwarden couldn't safely access the saved sign-in data in Keychain.")
            Text("Retry, or continue to a fresh sign-in. Existing saved items aren't cleared by retry.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") { coordinator.start() }
                .buttonStyle(.borderedProminent)
            Button("Continue to sign in") { coordinator.continueToServerSetup() }
                .buttonStyle(.bordered)
            Button("Clear saved sign-in…", role: .destructive) { coordinator.isConfirmingSignOut = true }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Clear this device's saved sign-in?", isPresented: Binding(
            get: { coordinator.isConfirmingSignOut }, set: { coordinator.isConfirmingSignOut = $0 }
        )) {
            Button("Sign out and clear saved data", role: .destructive) {
                Task {
                    guard coordinator.isCurrentRoute(id) else { return }
                    await coordinator.requestLogout()
                }
            }
        } message: {
            Text(
                "Saved sign-in data and AutoFill access on this device will be cleared. Your server vault will not be deleted."
            )
        }
    }
}
