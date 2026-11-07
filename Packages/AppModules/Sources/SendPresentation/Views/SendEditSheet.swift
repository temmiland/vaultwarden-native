import Domain
import SharedUI
import SwiftUI

struct SendEditSheet: View {
    let model: SendModel
    @State private var draft: SendDraft

    init(model: SendModel, draft: SendDraft) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                }

                switch draft.contentKind {
                case .text:
                    Section("Text") {
                        TextEditor(text: $draft.text)
                            .frame(minHeight: 100)
                        Toggle("Hide text by default", isOn: $draft.textHidden)
                    }
                case .file:
                    Section("File") {
                        if let pickedFileName = draft.pickedFileName {
                            LabeledContent("File", value: pickedFileName)
                        } else {
                            Text("A file Send's contents can't be replaced after it's created.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 60)
                }

                Section("Access") {
                    Toggle("Password Protected", isOn: $draft.hasPasswordProtection)
                    if draft.hasPasswordProtection {
                        SecureField(
                            draft.hadExistingPassword ? "New Password (leave blank to keep current)" : "Password",
                            text: $draft.password
                        )
                    }
                    Toggle("Limit Number of Accesses", isOn: $draft.hasMaxAccessCount)
                    if draft.hasMaxAccessCount {
                        Stepper("Max Accesses: \(draft.maxAccessCount)", value: $draft.maxAccessCount, in: 1 ... 1000)
                    }
                    Toggle("Hide My Email From Recipients", isOn: $draft.hidesEmail)
                    Toggle("Deactivate This Send", isOn: $draft.isDisabled)
                }

                Section("Dates") {
                    DatePicker(
                        "Deletion Date",
                        selection: $draft.deletionDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Toggle("Set Expiration Date", isOn: $draft.hasExpirationDate)
                    if draft.hasExpirationDate {
                        DatePicker(
                            "Expiration Date",
                            selection: $draft.expirationDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.editingID == nil ? "New Send" : "Edit Send")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.dismissDraft() }
                        .disabled(model.state.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateDraft(draft)
                        Task { await model.saveDraft() }
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .overlay {
                if model.state.isUploadingFile {
                    ProgressView("Uploading…")
                        .padding()
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10))
                } else if model.state.isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .platformMinSize(width: 420, height: 480)
    }

    private var isSaveDisabled: Bool {
        if model.state.isSaving { return true }
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if draft.contentKind == .text, draft.text.isEmpty { return true }
        if draft.contentKind == .file, draft.editingID == nil, draft.pickedFileName == nil { return true }
        if draft.hasPasswordProtection, !draft.hadExistingPassword, draft.password.isEmpty { return true }
        return false
    }
}
