import Domain

/// Scope even retained UI copy closures to their original session. Platform clipboard behavior
/// remains delegated to the injected client. Values copied before revocation are not retracted.
@MainActor
public final class SessionPasteboardClient: PasteboardClient {
    private let runtime: SessionRuntime
    private let base: any PasteboardClient

    public init(runtime: SessionRuntime, base: any PasteboardClient) {
        self.runtime = runtime
        self.base = base
    }

    public func copySecret(_ value: String) {
        guard (try? runtime.checkAccess()) != nil else { return }
        base.copySecret(value)
    }
}
