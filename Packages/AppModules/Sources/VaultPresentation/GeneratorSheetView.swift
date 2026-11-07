import Domain
import SwiftUI

struct GeneratorSheetView: View {
    let model: VaultModel
    @Environment(\.pasteboardClient) private var pasteboardClient

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(passwordLabel)
                            .font(.system(.title3, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            pasteboardClient?.copySecret(model.state.generatedPassword)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .disabled(model.state.generatedPassword.isEmpty)
                    }
                    if let message = model.state.generatorErrorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                    Button("Regenerate") {
                        Task { await model.perform(.regeneratePassword) }
                    }
                }

                Section("Options") {
                    let options = optionsBinding
                    Stepper("Length: \(options.wrappedValue.length)", value: options.length, in: 5 ... 128)
                    Toggle("Uppercase (A-Z)", isOn: options.useUppercase)
                    Toggle("Lowercase (a-z)", isOn: options.useLowercase)
                    Toggle("Numbers (0-9)", isOn: options.useNumbers)
                    Toggle("Special (!@#$%^&*)", isOn: options.useSpecial)
                    Toggle("Avoid Ambiguous Characters", isOn: options.avoidAmbiguous)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Password Generator")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.send(.generatorPresentedChanged(false)) }
                }
            }
            .task {
                if model.state.generatedPassword.isEmpty {
                    await model.perform(.regeneratePassword)
                }
            }
            .onChange(of: model.state.generatorOptions) {
                Task { await model.perform(.regeneratePassword) }
            }
        }
        .platformMinSize(width: 420, height: 380)
    }

    private var optionsBinding: Binding<PasswordGeneratorOptions> {
        model.binding(get: \.generatorOptions, send: VaultAction.generatorOptionsChanged)
    }

    private var passwordLabel: String {
        if !model.state.generatedPassword.isEmpty { return model.state.generatedPassword }
        return model.state.generatorErrorMessage == nil ? "Generating…" : "No password generated"
    }
}
