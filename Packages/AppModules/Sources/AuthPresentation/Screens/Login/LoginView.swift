import SharedUI
import SwiftUI

struct LoginView: View {
    let model: LoginModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Log in")
                .font(.title2.bold())
            Text(model.state.environment.baseURL.absoluteString)
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField(
                "Email",
                text: Binding(get: { model.state.email }, set: { model.receive(LoginAction.emailChanged($0)) })
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)
            .disableAutocorrection(true)
            .disabled(model.state.isLoading)

            SecureField(
                "Master password",
                text: Binding(get: { model.state.password }, set: { model.receive(LoginAction.passwordChanged($0)) })
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)
            .onSubmit { Task { await model.perform(.loginTapped) } }
            .disabled(model.state.isLoading)

            if let error = model.state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 360)
            }

            Button {
                Task { await model.perform(.loginTapped) }
            } label: {
                if model.state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Log in")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.state.isLoading)

            Button("Use a different server") {
                Task { await model.perform(.useDifferentServerTapped) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(model.state.isLoading)
        }
        .padding(40)
        .platformMinSize(width: 420, height: 340)
    }
}
