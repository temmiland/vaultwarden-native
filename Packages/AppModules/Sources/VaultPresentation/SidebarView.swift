import Domain
import SharedUI
import SwiftUI

struct SidebarView: View {
    let model: VaultModel

    var body: some View {
        List(selection: filterBinding) {
            Section("Vault") {
                Label("All Items", systemImage: "person.crop.circle.fill.badge.checkmark")
                    .tag(VaultFilter.allItems)
                Label("Favorites", systemImage: "star.fill")
                    .tag(VaultFilter.favorites)
            }

            Section("Types") {
                ForEach(VaultItemKind.editableKinds, id: \.self) { type in
                    Label(type.displayName + "s", systemImage: type.symbolName)
                        .tag(VaultFilter.type(type))
                }
            }

            if !model.state.folderSummaries.isEmpty {
                Section("Folders") {
                    ForEach(model.state.folderSummaries, id: \.id) { folder in
                        Label(folder.name, systemImage: "folder.fill")
                            .tag(VaultFilter.folder(folder.id))
                    }
                    Label("No Folder", systemImage: "folder")
                        .tag(VaultFilter.folder(nil))
                }
            }

            ForEach(collectionsByOrganization, id: \.organizationID) { group in
                Section(group.organizationName) {
                    ForEach(group.collections, id: \.id) { collection in
                        Label(collection.name, systemImage: "person.2.badge.gearshape.fill")
                            .tag(VaultFilter.collection(collection.id))
                    }
                }
            }
        }
        .navigationTitle("Vault")
    }

    /// Collections grouped by their owning organization (via `state.organizationNames`), sorted so
    /// the sidebar's org sections come out in a stable order.
    private var collectionsByOrganization: [
        (organizationID: OrganizationID, organizationName: String, collections: [VaultCollectionSummary])
    ] {
        let grouped = Dictionary(grouping: model.state.collectionSummaries, by: { $0.organizationID })
        return grouped
            .map { organizationID, collections in
                (
                    organizationID: organizationID,
                    organizationName: model.state.organizationName(for: organizationID) ?? "Collections",
                    collections: collections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
            .sorted { $0.organizationName.localizedCaseInsensitiveCompare($1.organizationName) == .orderedAscending }
    }

    private var filterBinding: Binding<VaultFilter?> {
        Binding(
            get: { model.state.filter },
            set: { newValue in if let newValue { model.send(.filterSelected(newValue)) } }
        )
    }
}
