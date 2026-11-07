import SharedUI
import SwiftUI

struct TwoFactorView: View {
    let model: TwoFactorModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Two-step login")
                .font(.title2.bold())
            Text("Enter the code from your authenticator app.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if model.state.providers.count > 1 {
                unsupportedProvidersNotice
            }

            TextField(
                "6-digit code",
                text: Binding(get: { model.state.code }, set: { model.receive(TwoFactorAction.codeChanged($0)) })
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)
            .onSubmit { Task { await model.perform(.submitTapped) } }
            .disabled(model.state.isLoading)

            Toggle(
                "Remember this device",
                isOn: Binding(get: { model.state.remember }, set: { model.receive(TwoFactorAction.rememberToggled($0)) })
            )
            .frame(maxWidth: 360)
            .disabled(model.state.isLoading)

            if let error = model.state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await model.perform(.submitTapped) }
            } label: {
                if model.state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Verify")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.state.isLoading)

            Button("Cancel") {
                Task { await model.perform(.cancelTapped) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(model.state.isLoading)
        }
        .padding(40)
        .platformMinSize(width: 420, height: 340)
    }

    private var unsupportedProvidersNotice: some View {
        let others = model.state.providers.filter { $0 != .authenticator }
        return Group {
            if !others.isEmpty {
                Text("Also available but not yet supported in this app: " +
                    others.map(\.displayName).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
            }
        }
    }
}
