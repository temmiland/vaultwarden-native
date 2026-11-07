import Data
import Domain
import Foundation
import Networking
import Testing

/// Runtime/transport fixtures without an SDK Client, live Keychain or network.
@Suite
struct SessionRuntimeTests {
    @Test
    func revocationIsPermanentAndLogoutCannotBeDowngradedToLock() async throws {
        let account = try makeAccount()
        let resource = RuntimeResource()
        let tokens = RuntimeTokens()
        let runtime = SessionRuntime(account: account, resource: resource, tokens: tokens)
        let states = await runtime.sessionStates()
        var iterator = states.makeAsyncIterator()
        #expect(await iterator.next() == .unlocked(account))
        #expect(await runtime.getAccessToken() == "fake-test-token")
        await runtime.revoke(.lock)
        #expect(await iterator.next() == .locked(account))
        #expect(!resource.isActive)
        #expect(throws: CancellationError.self) { try runtime.checkAccess() }
        #expect(await runtime.getAccessToken() == nil)
        await runtime.revoke(.logout)
        #expect(await iterator.next() == .signedOut)
        await runtime.revoke(.lock)
        #expect(await runtime.currentState() == .signedOut)
        #expect(await tokens.revocationCount == 1)

        let next = SessionRuntime(account: account, resource: RuntimeResource(), tokens: RuntimeTokens())
        #expect(next.id != runtime.id)
        #expect(await next.getAccessToken() == "fake-test-token")
        #expect(await runtime.getAccessToken() == nil)
    }

    @Test
    func anOldTokenLookupCannotReturnAfterRevocation() async throws {
        let barrier = RuntimeBarrier()
        let resource = RuntimeResource()
        let runtime = SessionRuntime(
            account: try makeAccount(),
            resource: resource,
            tokens: RuntimeTokens(barrier: barrier)
        )
        let lookup = Task { await runtime.getAccessToken() }
        await barrier.waitUntilPaused()
        await runtime.revoke(.expired)
        await barrier.release()
        #expect(await lookup.value == nil)
        #expect(await runtime.currentState() == .signedOut)
    }

    @Test
    func scopedTransportCancelsAndRejectsANonCooperativeLateResponse() async throws {
        let barrier = RuntimeBarrier()
        let transport = RuntimeTransport(barrier: barrier)
        let runtime = SessionRuntime(account: try makeAccount(), resource: RuntimeResource(), tokens: RuntimeTokens())
        let client = SessionHTTPClient(runtime: runtime, base: transport)
        let request = HTTPRequest(url: URL(string: "https://vault.example.com/api/sync")!, method: .get)
        let pending = Task { try await client.send(request) }
        await barrier.waitUntilPaused()
        await runtime.revoke(.lock)
        await barrier.release()
        do {
            _ = try await pending.value
            Issue.record("A revoked runtime must not return the late response")
        } catch is CancellationError {} catch { Issue.record("Expected lifetime cancellation") }
        #expect(await transport.returnedWhileCancelled)
        do {
            _ = try await client.send(request)
            Issue.record("A revoked client must not start another request")
        } catch is CancellationError {} catch { Issue.record("Expected lifetime cancellation") }
        #expect(await transport.sendCount == 1)
    }

    @Test
    func cancellingOneOperationDoesNotRevokeTheRuntime() async throws {
        let barrier = RuntimeBarrier()
        let resource = RuntimeResource()
        let runtime = SessionRuntime(account: try makeAccount(), resource: resource, tokens: RuntimeTokens())
        let pending = Task { try await runtime.perform { await barrier.pause(); return 1 } }
        await barrier.waitUntilPaused()
        pending.cancel()
        await barrier.release()
        do {
            _ = try await pending.value
            Issue.record("A cancelled caller must not receive a result")
        } catch is CancellationError {} catch { Issue.record("Expected cancellation") }
        #expect(resource.isActive)
        #expect(try await runtime.perform { 2 } == 2)
    }

    @MainActor
    @Test
    func retainedCopyClosuresCannotWriteToThePasteboardAfterLock() async throws {
        let runtime = SessionRuntime(account: try makeAccount(), resource: RuntimeResource(), tokens: RuntimeTokens())
        let pasteboard = RuntimePasteboard()
        let scoped = SessionPasteboardClient(runtime: runtime, base: pasteboard)
        scoped.copySecret("fake-test-secret-before-lock")
        await runtime.revoke(.lock)
        scoped.copySecret("fake-test-secret-after-lock")
        #expect(pasteboard.values == ["fake-test-secret-before-lock"])
    }

    @Test
    func runtimeMetadataPreservesExplicitServiceRoutes() throws {
        let environment = try ServerEnvironment(
            baseURL: URL(string: "https://vault.example.com/vault/")!,
            apiURL: URL(string: "https://api.example.com/custom")!,
            identityURL: URL(string: "https://identity.example.com/oauth")!,
            webVaultURL: URL(string: "https://web.example.com/vault")!
        )
        #expect(environment.baseURL.absoluteString == "https://vault.example.com/vault")
        #expect(environment.apiURL.absoluteString == "https://api.example.com/custom")
        #expect(environment.identityURL.absoluteString == "https://identity.example.com/oauth")
        #expect(environment.webVaultURL.absoluteString == "https://web.example.com/vault")
    }

    private func makeAccount() throws -> AccountSession {
        AccountSession(
            accountID: AccountID(rawValue: "test-account"),
            email: "test@example.com",
            environment: try ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
        )
    }
}

private final class RuntimeResource: SessionResource, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.withLock { active } }
    func revoke() { lock.withLock { active = false } }
}

@MainActor
private final class RuntimePasteboard: PasteboardClient {
    private(set) var values: [String] = []
    func copySecret(_ value: String) { values.append(value) }
}

private actor RuntimeTokens: SessionTokenProviding {
    private let barrier: RuntimeBarrier?
    private(set) var revocationCount = 0
    init(barrier: RuntimeBarrier? = nil) { self.barrier = barrier }
    func getAccessToken() async -> String? {
        if let barrier { await barrier.pause() }
        return "fake-test-token" // deliberately ignores revocation to exercise the runtime guard
    }

    func revoke() { revocationCount += 1 }
}

private actor RuntimeBarrier {
    private var paused = false
    private var pausedWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            paused = true
            for waiter in pausedWaiters { waiter.resume() }
            pausedWaiters = []
        }
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { pausedWaiters.append($0) }
    }

    func release() { continuation?.resume(); continuation = nil }
}

private actor RuntimeTransport: HTTPClient {
    let barrier: RuntimeBarrier
    private(set) var returnedWhileCancelled = false
    private(set) var sendCount = 0
    init(barrier: RuntimeBarrier) { self.barrier = barrier }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sendCount += 1
        await barrier.pause()
        returnedWhileCancelled = Task.isCancelled
        return HTTPResponse(statusCode: 200, headers: [:], body: Data("fake-test-payload".utf8))
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        try await send(request)
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        throw CancellationError() // no filesystem work in these fixtures
    }
}
