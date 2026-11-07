import SharedUI
import SwiftUI

struct UnlockView: View {
    let model: UnlockModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome back")
                .font(.title2.bold())
            Text(model.state.account.email)
                .font(.callout)
                .foregroundStyle(.secondary)

            if model.state.isBiometricAvailable {
                Button {
                    Task { await model.perform(.unlockWithBiometricsTapped) }
                } label: {
                    Label(
                        "Unlock with \(model.state.biometryKind.displayName)",
                        systemImage: model.state.biometryKind.systemImageName
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.state.isLoading)

                Text("or")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.state.isPinAvailable {
                SecureField(
                    "PIN",
                    text: Binding(get: { model.state.pin }, set: { model.receive(UnlockAction.pinChanged($0)) })
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .onSubmit { Task { await model.perform(.unlockWithPinTapped) } }
                .disabled(model.state.isLoading)

                Button {
                    Task { await model.perform(.unlockWithPinTapped) }
                } label: {
                    Label("Unlock with PIN", systemImage: "number")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.state.isLoading)

                Text("or")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField(
                "Master password",
                text: Binding(get: { model.state.password }, set: { model.receive(UnlockAction.passwordChanged($0)) })
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)
            .onSubmit { Task { await model.perform(.unlockWithPasswordTapped) } }
            .disabled(model.state.isLoading)

            if let error = model.state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await model.perform(.unlockWithPasswordTapped) }
            } label: {
                if model.state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Unlock")
                }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.defaultAction)
            .disabled(model.state.isLoading)

            Button("Log out") {
                Task { await model.perform(.logoutTapped) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(40)
        .platformMinSize(width: 420, height: 360)
        .task { await model.perform(.appeared) }
    }
}
