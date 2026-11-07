import Domain
import Foundation

/// Data's session-bound implementation of the Domain settings port. Presentation receives
/// neither credential storage nor a PIN-derived key. No PIN is retained or persisted.
public struct SessionPinUnlockSettings: PinUnlockSettings {
    private let runtime: SessionRuntime
    private let store: AuthCredentialStore
    private let deriveProtectedKey: @Sendable (String) async throws -> String

    public init(session: AuthenticatedSession, store: AuthCredentialStore) {
        self.init(
            runtime: session.runtime,
            store: store,
            deriveProtectedKey: { try await session.derivePINProtectedUserKey(pin: $0) }
        )
    }

    // Crypto is an injected operation at the Data/SDK boundary. Tests exercise this same
    // implementation without constructing a live SDK client or touching the user's Keychain.
    init(
        runtime: SessionRuntime,
        store: AuthCredentialStore,
        deriveProtectedKey: @escaping @Sendable (String) async throws -> String
    ) {
        self.runtime = runtime
        self.store = store
        self.deriveProtectedKey = deriveProtectedKey
    }

    public func enroll(pin: String) async throws {
        let scope = try await runtime.validatedTokenScope()
        let epoch = try store.returningUnlockEpoch(requiringScope: scope)
        try runtime.checkAccess()
        let protectedKey = try await deriveProtectedKey(pin)
        try runtime.checkAccess()
        guard try await runtime.validatedTokenScope() == scope else { throw CancellationError() }
        try runtime.checkAccess()
        try store.enrollPinProtectedUserKey(protectedKey, requiringScope: scope, publicationEpoch: epoch)
    }

    public func remove() async throws {
        let scope = try await runtime.validatedTokenScope()
        let epoch = try store.returningUnlockEpoch(requiringScope: scope)
        try runtime.checkAccess()
        try store.removePinUnlock(requiringScope: scope, publicationEpoch: epoch)
    }

    public func isEnabled() async throws -> Bool {
        let scope = try await runtime.validatedTokenScope()
        try runtime.checkAccess()
        return try store.pinUnlockState(requiringScope: scope).isEnabled
    }
}
