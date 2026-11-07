import AutoFillContract
import SwiftUI

/// Asks where a new passkey should be saved: into a login the user already has for this site, or
/// into a new item.
///
/// Offering the existing-item choice matters — sites commonly ask you to add a passkey to an
/// account you already have a password for, and silently creating a second, near-duplicate entry
/// for the same site is how vaults turn into a mess.
@MainActor
public struct PasskeyRegistrationView: View {
    let relyingPartyIdentifier: String
    let userName: String
    /// Existing logins for this site, offered as attach targets.
    let existingItems: [AutoFillLoginSummary]
    var warningMessage: String? = nil
    let isSaving: Bool
    var canSave = true
    let errorMessage: String?
    let onSaveToExisting: (AutoFillLoginSummary) -> Void
    let onSaveAsNewItem: () -> Void
    let onCancel: () -> Void

    public init(
        relyingPartyIdentifier: String,
        userName: String,
        existingItems: [AutoFillLoginSummary],
        warningMessage: String? = nil,
        isSaving: Bool,
        canSave: Bool = true,
        errorMessage: String?,
        onSaveToExisting: @escaping (AutoFillLoginSummary) -> Void,
        onSaveAsNewItem: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.userName = userName
        self.existingItems = existingItems
        self.warningMessage = warningMessage
        self.isSaving = isSaving
        self.canSave = canSave
        self.errorMessage = errorMessage
        self.onSaveToExisting = onSaveToExisting
        self.onSaveAsNewItem = onSaveAsNewItem
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let warningMessage {
                Label(warningMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            List {
                Section {
                    Button(action: onSaveAsNewItem) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save as a new item")
                                Text(relyingPartyIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if !existingItems.isEmpty {
                    Section("Or add to an existing login") {
                        ForEach(existingItems, id: \.id) { item in
                            Button {
                                onSaveToExisting(item)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                        if let username = item.username, !username.isEmpty {
                                            Text(username)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: "lock.fill")
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .disabled(isSaving || !canSave)
            .opacity(isSaving ? 0.4 : 1)
            .overlay {
                if isSaving {
                    ProgressView("Saving passkey…")
                }
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 340)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Save Passkey").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isSaving)
            }
            Text("\(userName) on \(relyingPartyIdentifier)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
