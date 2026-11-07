import Domain
import SharedUI
import SwiftUI

struct ItemEditSheet: View {
    let model: VaultModel
    @State var draft: VaultItemDraft
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Toggle("Favorite", isOn: $draft.favorite)
                    if !model.state.folderSummaries.isEmpty {
                        Picker("Folder", selection: $draft.folderID) {
                            Text("No Folder").tag(FolderID?.none)
                            ForEach(model.state.folderSummaries, id: \.id) { folder in
                                Text(folder.name).tag(Optional(folder.id))
                            }
                        }
                    }
                }

                switch draft.kind {
                case .login:
                    LoginEditFields(draft: $draft)
                case .card:
                    CardEditFields(draft: $draft)
                case .identity:
                    IdentityEditFields(draft: $draft)
                case .secureNote:
                    EmptyView() // notes field below covers it
                case .sshKey:
                    SshKeyEditFields(draft: $draft)
                case .bankAccount, .driversLicense, .passport, .unknown:
                    EmptyView()
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .navigationTitle(draft.editingID == nil ? "New \(draft.kind.displayName)" : "Edit \(draft.kind.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.send(.sheetDismissed) }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.send(.draftChanged(draft))
                        isSaving = true
                        Task {
                            await model.perform(.saveDraft)
                            isSaving = false
                        }
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .platformMinSize(width: 420, height: 480)
    }
}

private struct LoginEditFields: View {
    @Binding var draft: VaultItemDraft

    var body: some View {
        Section("Login") {
            TextField("Username", text: $draft.username)
            SecureField("Password", text: $draft.password)
            TextField("TOTP Seed (optional)", text: $draft.totpSeed)
        }
        Section("URIs") {
            ForEach(Array(draft.uris.indices), id: \.self) { index in
                TextField("URI", text: $draft.uris[index])
            }
            Button("Add URI") { draft.uris.append("") }
        }
    }
}

private struct CardEditFields: View {
    @Binding var draft: VaultItemDraft

    var body: some View {
        Section("Card") {
            TextField("Cardholder Name", text: $draft.cardholderName)
            TextField("Number", text: $draft.cardNumber)
            TextField("Brand", text: $draft.cardBrand)
            HStack {
                TextField("Exp. Month", text: $draft.cardExpMonth)
                TextField("Exp. Year", text: $draft.cardExpYear)
            }
            TextField("Security Code", text: $draft.cardCode)
        }
    }
}

private struct IdentityEditFields: View {
    @Binding var draft: VaultItemDraft

    var body: some View {
        Section("Identity") {
            TextField("First Name", text: $draft.firstName)
            TextField("Last Name", text: $draft.lastName)
            TextField("Username", text: $draft.identityUsername)
            TextField("Email", text: $draft.identityEmail)
            TextField("Phone", text: $draft.identityPhone)
        }
    }
}

private struct SshKeyEditFields: View {
    @Binding var draft: VaultItemDraft

    var body: some View {
        Section("SSH Key") {
            TextField("Public Key", text: $draft.sshPublicKey)
            TextField("Private Key", text: $draft.sshPrivateKey)
            TextField("Fingerprint", text: $draft.sshFingerprint)
        }
    }
}
