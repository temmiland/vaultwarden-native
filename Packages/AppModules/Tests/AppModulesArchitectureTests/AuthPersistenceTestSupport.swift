import AutoFillContract
import Data
import Domain
import Foundation
import SecurityStorage

/// Synchronized, in-memory stores for the migrated production persistence/provider tests.
/// No real credentials, entitlements, network or fallback file storage.
final class AuthKeychainFixture: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Foundation.Data] = [:]
    private var failingWrites: Set<String> = []
    private var failingReads: Set<String> = []
    private var cancellingReads: Set<String> = []
    private var failingRemoval: Set<String> = []
    private var storedProtections: [String: KeychainProtection] = [:]

    var accountsFailingWrites: Set<String> {
        get { lock.withLock { failingWrites } }
        set { lock.withLock { failingWrites = newValue } }
    }

    var accountsFailingReads: Set<String> {
        get { lock.withLock { failingReads } }
        set { lock.withLock { failingReads = newValue } }
    }

    var accountsCancellingReads: Set<String> {
        get { lock.withLock { cancellingReads } }
        set { lock.withLock { cancellingReads = newValue } }
    }

    var accountsFailingRemoval: Set<String> {
        get { lock.withLock { failingRemoval } }
        set { lock.withLock { failingRemoval = newValue } }
    }

    var protections: [String: KeychainProtection] { lock.withLock { storedProtections } }

    func write(_ value: Foundation.Data, for account: String, protection: KeychainProtection) throws {
        try lock.withLock {
            guard !failingWrites.contains(account) else { throw AuthFixtureError.operationFailed }
            storage[account] = value
            storedProtections[account] = protection
        }
    }

    func read(_ account: String) throws -> Foundation.Data {
        try lock.withLock {
            guard !cancellingReads.contains(account) else { throw KeychainStoreError.interactionCancelled }
            guard !failingReads.contains(account) else { throw AuthFixtureError.operationFailed }
            guard let value = storage[account] else { throw KeychainStoreError.notFound }
            return value
        }
    }

    func remove(_ account: String) throws {
        try lock.withLock {
            guard !failingRemoval.contains(account) else { throw AuthFixtureError.operationFailed }
            storage.removeValue(forKey: account)
        }
    }
}

enum AuthFixtureError: Error { case operationFailed }

final class AuthRefreshFixture: TokenRefreshing, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: TokenRefreshOutcome = .retryable(.transport)
    private var beforeReturn: (@Sendable () async -> Void)?
    private var callCount = 0

    var refreshOutcome: TokenRefreshOutcome {
        get { lock.withLock { outcome } }
        set { lock.withLock { outcome = newValue } }
    }

    var beforeRefreshReturns: (@Sendable () async -> Void)? {
        get { lock.withLock { beforeReturn } }
        set { lock.withLock { beforeReturn = newValue } }
    }

    var refreshCallCount: Int { lock.withLock { callCount } }

    func refreshToken(identityURL: URL, refreshToken: String) async -> TokenRefreshOutcome {
        let (result, hook) = lock.withLock {
            callCount += 1
            return (outcome, beforeReturn)
        }
        await hook?()
        return result
    }
}

extension SharedAccountInfo {
    static func fixture(userID: String = "user-1") -> Self {
        Self(
            userId: userID,
            email: "test@example.com",
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedPrivateKey: "fake-test-wrapped-private-key",
            serverBaseURL: URL(string: "https://vault.example.com")!
        )
    }
}

actor AuthOperationTestGate {
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var blocked: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation {
            blocked = $0
            paused = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() { blocked?.resume(); blocked = nil }
}

actor AuthInvocationProbe {
    private(set) var count = 0
    func record() { count += 1 }
}

final class AuthResourceFixture: SessionResource, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.withLock { active } }
    func revoke() { lock.withLock { active = false } }
}
