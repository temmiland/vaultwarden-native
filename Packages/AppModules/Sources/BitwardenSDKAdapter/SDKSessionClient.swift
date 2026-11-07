import BitwardenSdk
import Domain
import Foundation

/// One unlocked SDK client behind a permanent revocation boundary. Legacy synchronous crypto
/// ports require a small synchronized holder; no lock is held over SDK work or suspension.
/// Dropping the holder's reference is not a promise of zeroizing SDK-owned key memory.
public final class SDKSessionClient: SessionResource, @unchecked Sendable {
    private let lock = NSLock()
    private var client: Client?

    public init(client: Client) { self.client = client }

    /// Extension composition can create a scoped resource without obtaining a raw Client.
    public convenience init(tokenProvider: any ClientManagedTokens, settings: ClientSettings) {
        self.init(client: SDKClientFactory.makeClient(tokenProvider: tokenProvider, settings: settings))
    }

    public var isActive: Bool { lock.withLock { client != nil } }

    public func revoke() {
        let released = lock.withLock { let old = client; client = nil; return old }
        // SDK destruction must not execute under the holder's mutex either.
        withExtendedLifetime(released) {}
    }

    // Only adapter code can obtain a temporary client reference. Callers never receive it.
    func withClient<Value>(_ operation: (Client) throws -> Value) throws -> Value {
        let client = try activeClient()
        do {
            let value = try operation(client)
            try checkAccess()
            return value
        } catch {
            try checkAccess()
            throw error
        }
    }

    func withClient<Value>(_ operation: (Client) async throws -> Value) async throws -> Value {
        let client = try activeClient()
        do {
            let value = try await operation(client)
            try checkAccess()
            return value
        } catch {
            try checkAccess()
            throw error
        }
    }

    func checkAccess() throws {
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
    }

    private func activeClient() throws -> Client {
        try Task.checkCancellation()
        return try lock.withLock {
            guard let client else { throw CancellationError() }
            return client
        }
    }
}
