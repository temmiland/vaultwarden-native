import Domain
import SharedUI
import SwiftUI

/// Picks the vault's layout from the available width rather than the platform.
///
/// A three-column `NavigationSplitView` is right on macOS and on a regular-width iPad, but on a
/// phone (and a narrow iPad split-screen slice) SwiftUI collapses it into a stack whose *root* is
/// the sidebar - so the app would open on the filter list ("All Items / Favorites / Types…")
/// instead of on the user's items, every single launch. The compact layout below opens on the
/// items and demotes the filter to a toolbar menu.
struct VaultSplitView: View {
    let model: VaultModel

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        layout.vaultSharedBehaviour(model: model)
    }

    /// `#if` rather than a runtime check on both sides: the compact layout uses `topBar*` toolbar
    /// placements, which don't exist on macOS, so it must not be compiled there at all.
    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
            if horizontalSizeClass == .compact {
                VaultCompactLayout(model: model)
            } else {
                VaultRegularLayout(model: model)
            }
        #else
            VaultRegularLayout(model: model)
        #endif
    }
}

// MARK: - Regular width (macOS, iPad)

private struct VaultRegularLayout: View {
    let model: VaultModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
        } content: {
            ItemListView(model: model)
        } detail: {
            ItemDetailView(model: model)
        }
        .searchable(
            text: model.binding(get: \.searchQuery, send: VaultAction.searchQueryChanged),
            placement: .sidebar,
            prompt: "Search vault"
        )
        .toolbar {
            ToolbarItemGroup {
                VaultToolbarButtons(model: model)
            }
        }
    }
}

// MARK: - Compact width (iPhone, narrow iPad slice)

#if os(iOS)
    private struct VaultCompactLayout: View {
        let model: VaultModel

        var body: some View {
            NavigationStack {
                ItemListView(model: model, usesSelectionBinding: false)
                    .searchable(
                        text: model.binding(get: \.searchQuery, send: VaultAction.searchQueryChanged),
                        prompt: "Search vault"
                    )
                    // Driven by the same `selectedItemID` the multi-column layout uses, so the
                    // Processor stays unaware of which layout is on screen. Writing `nil` back (the
                    // navigation bar's Back button) clears the selection.
                    .navigationDestination(
                        item: model.binding(get: \.selectedItemID, send: VaultAction.itemSelected)
                    ) { _ in
                        ItemDetailView(model: model)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            VaultFilterMenu(model: model)
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            VaultToolbarButtons(model: model)
                        }
                    }
            }
        }
    }

    /// The sidebar's job, folded into a single menu for the compact layout.
    private struct VaultFilterMenu: View {
        let model: VaultModel

        var body: some View {
            Menu {
                Picker("Filter", selection: model.binding(get: \.filter, send: VaultAction.filterSelected)) {
                    Label("All Items", systemImage: "person.crop.circle.fill.badge.checkmark")
                        .tag(VaultFilter.allItems)
                    Label("Favorites", systemImage: "star.fill")
                        .tag(VaultFilter.favorites)

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

                    if !model.state.collectionSummaries.isEmpty {
                        Section("Collections") {
                            ForEach(model.state.collectionSummaries, id: \.id) { collection in
                                Label(collection.name, systemImage: "person.2.badge.gearshape.fill")
                                    .tag(VaultFilter.collection(collection.id))
                            }
                        }
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
#endif

// MARK: - Shared pieces

private struct VaultToolbarButtons: View {
    let model: VaultModel

    var body: some View {
        Menu {
            ForEach(VaultItemKind.editableKinds, id: \.self) { type in
                Button {
                    model.send(.addItemTapped(type))
                } label: {
                    Label("New \(type.displayName)", systemImage: type.symbolName)
                }
            }
        } label: {
            Label("Add Item", systemImage: "plus")
        }

        Button {
            model.send(.generatorPresentedChanged(true))
        } label: {
            Label("Password Generator", systemImage: "wand.and.stars")
        }

        Button {
            model.send(.logoutTapped)
        } label: {
            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }
}

/// Sheets, alerts and the initial load - identical in both layouts, so they hang off the container
/// rather than being duplicated into each.
private struct VaultSharedBehaviour: ViewModifier {
    let model: VaultModel

    func body(content: Content) -> some View {
        content
            .task {
                await model.perform(.loadVault)
            }
            .overlay {
                if model.state.isLoading {
                    ProgressView("Syncing vault…")
                }
            }
            .sheet(
                isPresented: model.binding(get: \.isGeneratorPresented, send: VaultAction.generatorPresentedChanged)
            ) {
                GeneratorSheetView(model: model)
            }
            .sheet(item: sheetBinding) { sheet in
                ItemEditSheet(model: model, draft: sheet.draft)
            }
            .alert(
                "Delete this item?",
                isPresented: Binding(
                    get: { model.state.pendingDeleteID != nil },
                    set: { isPresented in if !isPresented { model.send(.deleteCancelled) } }
                )
            ) {
                Button("Cancel", role: .cancel) { model.send(.deleteCancelled) }
                Button("Delete", role: .destructive) {
                    Task { await model.perform(.confirmDelete) }
                }
            } message: {
                Text("This can't be undone.")
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { model.state.errorMessage != nil },
                    set: { isPresented in if !isPresented { model.send(.errorDismissed) } }
                )
            ) {
                Button("OK") { model.send(.errorDismissed) }
            } message: {
                Text(model.state.errorMessage ?? "")
            }
    }

    /// The system only ever *writes* `nil` to this binding (when the user dismisses the sheet);
    /// presenting a sheet always goes through `.addItemTapped`/`.editItemTapped` mutating state
    /// directly in the Processor.
    private var sheetBinding: Binding<VaultSheet?> {
        Binding(
            get: { model.state.sheet },
            set: { newValue in if newValue == nil { model.send(.sheetDismissed) } }
        )
    }
}

private extension View {
    func vaultSharedBehaviour(model: VaultModel) -> some View {
        modifier(VaultSharedBehaviour(model: model))
    }
}
