import AutoFillData
import Domain
import Foundation
import Testing

@Suite @MainActor
struct AutoFillTOTPExpiryTests {
    @Test(arguments: [UInt32(30), 60, 45])
    func validityEndsAtEpochAlignedBoundaryNotGenerationPlusPeriod(_ period: UInt32) throws {
        let boundary = Double(period) * 4
        let code = TimeBasedOneTimeCode(
            code: "123456",
            period: period,
            generatedAt: Date(timeIntervalSince1970: boundary - 0.1)
        )
        try code.validate(at: Date(timeIntervalSince1970: boundary - 0.001))
        #expect(throws: TimeBasedOneTimeCodeError.expired) { try code.validate(at: Date(timeIntervalSince1970: boundary)) }
        #expect(throws: TimeBasedOneTimeCodeError.expired) { try code.validate(
            at: Date(timeIntervalSince1970: boundary + 0.1)
        ) }
        #expect(throws: TimeBasedOneTimeCodeError.expired) { try code.validate(
            at: Date(timeIntervalSince1970: boundary - 0.2)
        ) }
    }

    @Test(arguments: ["empty", "zero", "negative", "nonfinite-generated", "nonfinite-now"])
    func malformedTimingOrCodeNeverGetsFilled(_ scenario: String) {
        let code = TimeBasedOneTimeCode(
            code: scenario == "empty" ? "" : "123456",
            period: scenario == "zero" ? 0 : 30,
            generatedAt: Date(
                timeIntervalSince1970: scenario == "negative" ? -1 : (scenario == "nonfinite-generated" ? .infinity : 31)
            )
        )
        #expect(throws: TimeBasedOneTimeCodeError.invalidMetadata) {
            try code.validate(at: Date(timeIntervalSince1970: scenario == "nonfinite-now" ? .infinity : 32))
        }
        #expect(!String(reflecting: code).contains("123456"))
    }

    @Test
    func generationAcrossBoundaryRegeneratesOnceAtExplicitFreshDate() async throws {
        let clock = TOTPTestClock(29.9), source = AutoFillQuerySourceFixture()
        source.onCode { clock.set(30.1) }
        let value = try await CredentialQuery(source: source, now: { clock.now() }).oneTimeCode(cipherId: "cipher-1")
        #expect(
            value.generatedAt == Date(timeIntervalSince1970: 30.1) && source.dates == [
                Date(timeIntervalSince1970: 29.9),
                Date(timeIntervalSince1970: 30.1),
            ]
        )
        #expect(source.seeds.count == 2 && source.decryptedIDs == ["cipher-1"])
    }

    @Test
    func repeatedRolloverIsBoundedAndNeverReturnsAnExpiredCode() async {
        let clock = TOTPTestClock(29.9), source = AutoFillQuerySourceFixture()
        source.onCode { clock.advance(30) }
        await #expect(throws: TimeBasedOneTimeCodeError.expired) {
            try await CredentialQuery(source: source, now: { clock.now() }).oneTimeCode(cipherId: "cipher-1")
        }
        #expect(source.seeds.count == 2)
    }

    @Test
    func invalidPeriodDoesNotCauseRegeneration() async {
        let source = AutoFillQuerySourceFixture(); source.setCodePeriod(0)
        await #expect(throws: TimeBasedOneTimeCodeError.invalidMetadata) {
            try await CredentialQuery(source: source).oneTimeCode(cipherId: "cipher-1")
        }
        #expect(source.seeds.count == 1)
    }

    @Test
    func boundaryBetweenQueryAndContextNeverDispatchesOldCodeAndAllowsTypedCancel() async throws {
        let clock = TOTPTestClock(29.9), source = AutoFillQuerySourceFixture()
        let value = try await CredentialQuery(source: source, now: { clock.now() }).oneTimeCode(cipherId: "cipher-1")
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle, now: { clock.now() })
        clock.set(30)
        #expect(throws: TimeBasedOneTimeCodeError.expired) {
            try completion.complete(
                .oneTimeCode(value),
                invocationID: id,
                checkAccess: { _ = try source.readCache() },
                context: context,
                retire: {}
            )
        }
        #expect(lifecycle.isActive(id) && context.outputs.isEmpty)
        #expect(completion.cancel(
            AutoFillRequestErrorPolicy.cancellation(for: TimeBasedOneTimeCodeError.expired, route: .identifiedCredential),
            invocationID: id,
            context: context,
            retire: {}
        ))
        #expect(context.cancellations == [.userInteractionRequired])
    }

    @Test
    func boundaryInsideFinalAccessCheckIsStillRejectedBeforeClaim() throws {
        let clock = TOTPTestClock(29.9), lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin(
        )
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle, now: { clock.now() })
        let value = TimeBasedOneTimeCode(code: "123456", period: 30, generatedAt: clock.now())
        #expect(throws: TimeBasedOneTimeCodeError.expired) {
            try completion.complete(
                .oneTimeCode(value),
                invocationID: id,
                checkAccess: { clock.set(30) },
                context: context,
                retire: {}
            )
        }
        #expect(context.outputs.isEmpty && lifecycle.isActive(id))
    }
}

private final class TOTPTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval
    init(_ value: TimeInterval) { self.value = value }
    func now() -> Date { lock.withLock { Date(timeIntervalSince1970: value) } }
    func set(_ value: TimeInterval) { lock.withLock { self.value = value } }
    func advance(_ delta: TimeInterval) { lock.withLock { value += delta } }
}
