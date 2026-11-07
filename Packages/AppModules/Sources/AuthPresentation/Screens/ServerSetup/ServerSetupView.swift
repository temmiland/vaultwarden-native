import SharedUI
import SwiftUI

struct ServerSetupView: View {
    let model: ServerSetupModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect to your server")
                .font(.title2.bold())
            Text("Enter the base URL of your self-hosted Vaultwarden instance.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField(
                "https://vault.example.com",
                text: Binding(get: { model.state.urlText }, set: { model.receive(ServerSetupAction.urlTextChanged($0)) })
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)
            .onSubmit { Task { await model.perform(.continueTapped) } }

            if let error = model.state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Continue") {
                Task { await model.perform(.continueTapped) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .platformMinSize(width: 420, height: 280)
    }
}
