import Foundation

/// One screen-owned operation at a time. UI cancellation is forwarded to the owned task;
/// retiring a route permanently cancels it, even if its view or an external caller stays alive.
/// This is task lifetime only, not auth authority: persistence still checks its sign-in/epoch.
@MainActor
final class AuthOperationLifetime {
    private var task: Task<Void, Never>?
    private(set) var isRetired = false
    var isRunning: Bool { task != nil }

    deinit { task?.cancel() }

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        guard !isRetired, task == nil, !Task.isCancelled else { return }
        let pending = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await operation()
        }
        task = pending
        await withTaskCancellationHandler {
            await pending.value
        } onCancel: {
            pending.cancel()
        }
        task = nil
    }

    func retire() {
        isRetired = true
        task?.cancel()
    }
}
