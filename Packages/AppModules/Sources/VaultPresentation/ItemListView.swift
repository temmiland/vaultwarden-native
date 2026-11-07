import Domain
import SharedUI
import SwiftUI

struct ItemListView: View {
    let model: VaultModel

    /// `true` in the multi-column layout, where `List` selection drives a permanently visible
    /// detail column. `false` in the compact stack layout, where selection has to *push* a detail
    /// screen instead - plain `List` selection does nothing on a phone outside edit mode, so rows
    /// become buttons there and the push is driven by `selectedItemID` changing.
    var usesSelectionBinding: Bool = true

    var body: some View {
        let items = model.state.visibleItems
        List(selection: usesSelectionBinding
            ? model.binding(get: \.selectedItemID, send: VaultAction.itemSelected)
            : .constant(nil)
        ) {
            if let lastSync = model.state.snapshot.lastSuccessfulSync {
                Section {
                    Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.state.snapshot.isStale || (model.state.snapshot.lastSuccessfulSync != nil &&
                model.state.snapshot.projectionStatus != .current(revision: model.state.snapshot.revision)) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Vault needs attention", systemImage: "exclamationmark.triangle")
                        Text(model.state.snapshot.isStale
                            ? "The displayed vault may be outdated. Sync before making further changes."
                            : "AutoFill cache or system suggestions couldn't be updated. Enable AutoFill and retry sync.")
                            .font(.caption)
                        Button("Retry Sync") { Task { await model.perform(.loadVault) } }
                            .disabled(model.state.isLoading)
                    }
                }
            }
            if model.state.loadWarnings.contains(.passkeyRegistrationRecoveryPending) {
                Section {
                    Label("Passkey write needs recovery", systemImage: "exclamationmark.triangle")
                    Text(
                        "Don't register again yet. Retry sync to verify the saved passkey and repair AutoFill. If this warning remains, inspect the vault in an official client; the write is still unresolved."
                    )
                    .font(.caption)
                    Button("Retry Sync") { Task { await model.perform(.loadVault) } }
                        .disabled(model.state.isLoading)
                    Button("Review Unresolved Write") { Task { await model.perform(.reviewPasskeyRegistrationRecovery) } }
                        .disabled(model.state.isLoading || model.state.isPasskeyRecoveryBusy)
                }
            }
            if model.state.unavailableItemCount > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Vault only partly loaded", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(unavailableItemsMessage)
                            .font(.caption)
                        Button("Retry Sync") {
                            Task { await model.perform(.loadVault) }
                        }
                        .disabled(model.state.isLoading)
                    }
                    .padding(.vertical, 4)
                }
            }
            if items.isEmpty, !model.state.isLoading {
                ContentUnavailableView(
                    model.state.unavailableItemCount > 0 ? "No Readable Items" : "No Items",
                    systemImage: "tray",
                    description: Text(
                        model.state.searchQuery.isEmpty ? "This filter has no items." : "No items match your search."
                    )
                )
            } else {
                ForEach(items, id: \.id) { item in
                    row(for: item)
                        .contextMenu {
                            if item.isEditable {
                                Button("Edit") {
                                    model.send(.editItemTapped(item.id))
                                }
                                if item.canDelete {
                                    Button("Delete", role: .destructive) {
                                        model.send(.deleteItemTapped(item.id))
                                    }
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle(model.state.filter.title.isEmpty ? "Items" : model.state.filter.title)
        .sheet(item: Binding(get: { model.state.passkeyRecoveryReview }, set: { value in
            if value == nil { model.send(.passkeyRecoveryReviewDismissed) }
        })) { review in
            PasskeyRecoveryReviewView(model: model, review: review)
                .id(review.id) // never carry checkbox consent into another nonce/review
        }
        #if os(macOS)
        .frame(minWidth: 260)
        #endif
    }

    private var unavailableItemsMessage: String {
        let count = model.state.unavailableItemCount
        let subject = count == 1 ? "1 item couldn't be loaded" : "\(count) items couldn't be loaded"
        return "\(subject). This list is incomplete. Retry sync; unavailable items cannot be edited here."
    }

    @ViewBuilder
    private func row(for item: VaultItemSummary) -> some View {
        if usesSelectionBinding {
            ItemRow(item: item).tag(Optional(item.id))
        } else {
            Button {
                model.send(.itemSelected(item.id))
            } label: {
                HStack {
                    ItemRow(item: item)
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ItemRow: View {
    let item: VaultItemSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.hasPasskeys {
                Image(systemName: "person.badge.key.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Has passkey")
            }
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, 2)
    }
}
