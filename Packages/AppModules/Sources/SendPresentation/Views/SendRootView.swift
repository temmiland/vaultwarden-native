import Domain
import SwiftUI

/// Entry point for the Send feature. App composition supplies the authenticated runtime; the
/// screen itself is driven by an observable model and repository rather than a Store/Coordinator.
public struct SendRootView: View {
    @State private var model: SendModel

    public init(
        repository: any SendRepository,
        checkSessionAccess: @escaping @Sendable () throws -> Void,
        sessionStates: @escaping @Sendable () async -> AsyncStream<SessionState>,
        fileImportClient: any FileImportClient,
        pasteboardClient: any PasteboardClient
    ) {
        _model = State(initialValue: SendModel(
            repository: repository,
            fileImportClient: fileImportClient,
            pasteboardClient: pasteboardClient,
            checkSessionAccess: checkSessionAccess,
            sessionStates: sessionStates
        ))
    }

    public var body: some View {
        SendSplitView(model: model)
    }
}
