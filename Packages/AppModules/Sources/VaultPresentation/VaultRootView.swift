import Domain
import SwiftUI

/// Dependencies are assembled by the app, and the screen's model survives body re-evaluation.
@MainActor
public struct VaultRootView: View {
    @State private var model: VaultModel
    private let pasteboardClient: any PasteboardClient

    public init(
        repository: any VaultRepository,
        generator: any PasswordGenerating,
        checkSessionAccess: @escaping @Sendable () throws -> Void,
        onLogout: @escaping () -> Void,
        fileImportClient: any FileImportClient,
        pasteboardClient: any PasteboardClient,
        removeTemporaryFile: @escaping @Sendable (URL) async throws -> Void
    ) {
        _model = State(initialValue: VaultModel(
            repository: repository, generator: generator, fileImportClient: fileImportClient,
            removeTemporaryFile: removeTemporaryFile,
            checkSessionAccess: checkSessionAccess, onLogout: onLogout
        ))
        self.pasteboardClient = pasteboardClient
    }

    public var body: some View {
        VaultSplitView(model: model).environment(\.pasteboardClient, pasteboardClient)
    }
}

extension VaultModel {
    func binding<Value>(get keyPath: KeyPath<VaultState, Value>, send action: @escaping (Value) -> VaultAction) -> Binding<
        Value
    > {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { self.send(action($0)) }
        )
    }
}
