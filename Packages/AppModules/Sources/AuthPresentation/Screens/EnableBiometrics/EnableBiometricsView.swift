import SharedUI
import SwiftUI

struct EnableBiometricsView: View {
    let model: EnableBiometricsModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: model.state.biometryKind.systemImageName)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Enable \(model.state.biometryKind.displayName)?")
                .font(.title2.bold())
            Text(
                "Use \(model.state.biometryKind.displayName) to unlock your vault instead of typing your master password every time."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 360)

            if !model.state.isBiometricAvailable {
                Text("Biometric unlock isn't available on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Not Now") {
                    Task { await model.perform(.skipTapped) }
                }
                .buttonStyle(.bordered)
                .disabled(model.state.isProcessing)

                Button {
                    Task { await model.perform(.enableTapped) }
                } label: {
                    if model.state.isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Enable \(model.state.biometryKind.displayName)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.state.isBiometricAvailable || model.state.isProcessing)
            }
        }
        .padding(40)
        .platformMinSize(width: 420, height: 320)
        .task { await model.perform(.appeared) }
    }
}
