import Domain
import Foundation
import LocalAuthentication
@testable import PlatformServices
import Testing

@Suite
struct SystemPasskeyUserVerifierTests {
    @Test(arguments: ["user", "system", "failed", "foreign-domain"])
    func onlyExplicitPlatformUserCancellationIsTerminal(_ scenario: String) async throws {
        let code = scenario == "system" ? LAError.systemCancel.rawValue :
            (scenario == "failed" ? LAError.authenticationFailed.rawValue : LAError.userCancel.rawValue)
        let error = NSError(domain: scenario == "foreign-domain" ? "fixture" : LAError.errorDomain, code: code)
        let context = PasskeyVerificationContextFixture(failure: error)
        let verifier = SystemPasskeyUserVerifier(makeContext: { context })
        if scenario == "user" {
            await #expect(throws: PasskeyUserVerificationError.userCanceled) { try await verifier.verify(reason: "test") }
        } else { #expect(try await !verifier.verify(reason: "test")) }
        #expect(context.calls == 1)
    }

    @Test
    func unavailableContextDoesNotPromptOrInventVerification() async throws {
        let context = PasskeyVerificationContextFixture(available: false)
        let verifier = SystemPasskeyUserVerifier(makeContext: { context })
        #expect(!verifier.isVerificationAvailable())
        #expect(try await !verifier.verify(reason: "test"))
        #expect(context.calls == 0)
    }

    @Test(arguments: ["success", "false", "error"])
    func platformResultAndRejectionAreMappedWithoutCachedAuthorization(_ scenario: String) async throws {
        let context = PasskeyVerificationContextFixture(result: scenario == "success", fails: scenario == "error")
        let verifier = SystemPasskeyUserVerifier(makeContext: { context })
        #expect(verifier.isVerificationAvailable())
        #expect(try await verifier.verify(reason: "test") == (scenario == "success"))
        #expect(try await verifier.verify(reason: "test") == (scenario == "success"))
        #expect(context.calls == 2 && context.reason == "test")
    }

    @Test
    func alreadyCancelledVerificationDoesNotCreateAContext() async throws {
        let gate = AuthOperationTestGate()
        let verifier = SystemPasskeyUserVerifier(
            makeContext: { Issue.record("Cancelled verification must not create LA context"); return PasskeyVerificationContextFixture(
            ) }
        )
        let task = Task { await gate.pause(); return try await verifier.verify(reason: "test") }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: [false, true])
    func cancellationRejectsLateSuccessOrPlatformError(_ fails: Bool) async throws {
        let context = PasskeyVerificationContextFixture(fails: fails, gate: AuthOperationTestGate())
        // The evaluation gate deliberately ignores cancellation, like a late OS callback.
        let verifier = SystemPasskeyUserVerifier(makeContext: { context })
        let task = Task { try await verifier.verify(reason: "test") }
        guard let evaluationGate = context.gate else { Issue.record("Missing fixture gate"); return }
        await evaluationGate.waitUntilPaused(); task.cancel(); await evaluationGate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

private final class PasskeyVerificationContextFixture: PasskeyVerificationContext, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var lastReason: String?
    let available: Bool, result: Bool, fails: Bool
    let gate: AuthOperationTestGate?
    let failure: (any Error)?
    init(
        available: Bool = true,
        result: Bool = true,
        fails: Bool = false,
        gate: AuthOperationTestGate? = nil,
        failure: (any Error)? = nil
    ) {
        self.available = available; self.result = result; self.fails = fails; self.gate = gate
        self.failure = failure
    }

    var calls: Int { lock.withLock { count } }
    var reason: String? { lock.withLock { lastReason } }
    func canVerify() -> Bool { available }
    func evaluate(reason: String) async throws -> Bool {
        lock.withLock { count += 1; lastReason = reason }
        await gate?.pause()
        if let failure { throw failure }
        if fails { throw PasskeyRecoveryFixtureError.storage }
        return result
    }
}
