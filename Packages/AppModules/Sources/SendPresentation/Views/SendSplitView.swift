import SwiftUI

struct SendSplitView: View {
    let model: SendModel

    var body: some View {
        NavigationSplitView {
            SendListPane(model: model)
        } detail: {
            SendDetailPane(model: model)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.beginNewTextSend() } label: {
                    Label("New Text Send", systemImage: "doc.text")
                }
                Button { Task { await model.pickFileSend() } } label: {
                    Label("New File Send", systemImage: "doc")
                }
            }
        }
        .task { await model.load() }
        .overlay {
            if model.state.isLoading {
                ProgressView("Loading Sends…")
            }
        }
        .sheet(isPresented: draftPresented) {
            if let draft = model.state.draft {
                SendEditSheet(model: model, draft: draft)
            }
        }
        .alert(
            "Delete this Send?",
            isPresented: Binding(
                get: { model.state.pendingDeleteID != nil },
                set: { if !$0 { model.cancelDelete() } }
            )
        ) {
            Button("Cancel", role: .cancel) { model.cancelDelete() }
            Button("Delete", role: .destructive) { Task { await model.confirmDelete() } }
                .disabled(model.state.isDeleting)
        } message: {
            Text("Anyone with the link will immediately lose access. This can't be undone.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.state.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.state.errorMessage ?? "")
        }
        .alert(
            "Couldn't open this Send",
            isPresented: Binding(
                get: { model.state.detailErrorMessage != nil },
                set: { if !$0 { model.dismissDetailError() } }
            )
        ) {
            Button("OK") { model.dismissDetailError() }
        } message: {
            Text(model.state.detailErrorMessage ?? "")
        }
        .alert(
            "Couldn't build a link",
            isPresented: Binding(
                get: { model.state.linkErrorMessage != nil },
                set: { if !$0 { model.dismissLinkError() } }
            )
        ) {
            Button("OK") { model.dismissLinkError() }
        } message: {
            Text(model.state.linkErrorMessage ?? "")
        }
    }

    private var draftPresented: Binding<Bool> {
        Binding(
            get: { model.state.draft != nil },
            set: { if !$0 { model.dismissDraft() } }
        )
    }
}
