import AutoFillContract
import SwiftUI

@MainActor
public struct PasswordSaveView: View {
    private let service: String
    private let existingItems: [AutoFillLoginSummary]
    private let isSaving: Bool
    private let canSave: Bool
    private let errorMessage: String?
    private let onSave: (String, AutoFillLoginSummary?) -> Void
    private let onCancel: () -> Void
    @State private var username: String

    public init(
        service: String,
        username: String,
        existingItems: [AutoFillLoginSummary],
        isSaving: Bool,
        canSave: Bool,
        errorMessage: String?,
        onSave: @escaping (String, AutoFillLoginSummary?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.service = service; self.existingItems = existingItems; self.isSaving = isSaving
        self.canSave = canSave; self.errorMessage = errorMessage; self.onSave = onSave; self.onCancel = onCancel
        _username = State(initialValue: username)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Save Password").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel).disabled(isSaving)
            }
            Text(service).font(.subheadline).textSelection(.enabled)
            TextField("Username", text: $username).textFieldStyle(.roundedBorder).disabled(isSaving)
            Text("Save the password supplied by this site to your unlocked vault.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if isSaving { ProgressView("Saving password…") }
            List {
                Button("Save as a new login") { onSave(username, nil) }
                if !existingItems.isEmpty {
                    Section("Update an existing login") {
                        ForEach(existingItems) { item in
                            Button { onSave(username, item) } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(item.username ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .disabled(isSaving || !canSave || username.isEmpty)
        }
        .padding()
    }
}
