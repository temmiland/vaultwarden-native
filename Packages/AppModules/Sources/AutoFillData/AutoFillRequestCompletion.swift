import Foundation

/// Live controller terminal boundary. It retains only lifecycle metadata, never output/context.
@MainActor
public final class AutoFillRequestCompletion {
    private let lifecycle: ExtensionRequestLifecycle
    private let now: @Sendable () -> Date
    public init(lifecycle: ExtensionRequestLifecycle, now: @escaping @Sendable () -> Date = { Date() }) {
        self.lifecycle = lifecycle; self.now = now
    }

    @discardableResult
    public func complete(
        _ credential: AutoFillCompletion,
        invocationID: UUID,
        checkAccess: () throws -> Void,
        context: any AutoFillExtensionContext,
        retire: () -> Void
    ) throws -> Bool {
        guard lifecycle.isActive(invocationID) else { return false }
        try Task.checkCancellation()
        try checkAccess()
        guard context.supports(credential.kind) else { throw AutoFillCompletionError.unsupportedRequest }
        try credential.validate(at: now())
        try Task.checkCancellation()
        guard lifecycle.claimCompletion(invocationID) else { return false }
        // No suspension or controller teardown between claim and platform dispatch. Teardown
        // may reenter; dispatch first, then retire only if the invocation is still current.
        context.complete(credential)
        if lifecycle.isCurrent(invocationID) { retire() }
        return true
    }

    @discardableResult
    public func cancel(
        _ reason: AutoFillCancellationReason,
        invocationID: UUID,
        context: any AutoFillExtensionContext,
        retire: () -> Void
    ) -> Bool {
        guard lifecycle.claimCompletion(invocationID) else { return false }
        context.cancel(reason)
        if lifecycle.isCurrent(invocationID) { retire() }
        return true
    }
}
