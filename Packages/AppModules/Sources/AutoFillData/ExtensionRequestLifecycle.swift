import Foundation

/// Pure orchestration gate; no OS extension context or credential payload is retained here.
@MainActor
public final class ExtensionRequestLifecycle {
    private var currentID: UUID?
    private var finished = false
    private var performingAction = false

    public init() {}

    @discardableResult
    public func begin() -> UUID {
        let id = UUID()
        currentID = id
        finished = false
        performingAction = false
        return id
    }

    public func isActive(_ id: UUID) -> Bool { currentID == id && !finished }
    public func isCurrent(_ id: UUID) -> Bool { currentID == id }

    public func beginAction(_ id: UUID) -> Bool {
        guard isActive(id), !performingAction else { return false }
        performingAction = true
        return true
    }

    public func endAction(_ id: UUID) {
        guard isActive(id) else { return }
        performingAction = false
    }

    /// Completion and cancellation share this gate: at most one terminal API call per invocation.
    public func claimCompletion(_ id: UUID) -> Bool {
        guard isActive(id) else { return false }
        finished = true
        return true
    }
}
