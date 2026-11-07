import AutoFillData
import Domain
import Foundation
import Testing

@Suite @MainActor
struct AutoFillRequestCompletionTests {
    @Test(arguments: [AutoFillCompletionKind.password, .oneTimeCode, .passkeyAssertion, .passkeyRegistration])
    func eachOutputStartsExactlyOneContextCallBeforeRetirement(_ kind: AutoFillCompletionKind) throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle), id = lifecycle.begin()
        var checks = 0, retired = 0
        context.onComplete = { #expect(retired == 0) }
        #expect(
            try completion.complete(
                Self.payload(kind),
                invocationID: id,
                checkAccess: { checks += 1 },
                context: context,
                retire: { retired += 1 }
            )
        )
        #expect(!completion.cancel(.failed, invocationID: id, context: context, retire: { retired += 1 }))
        #expect(
            try !completion.complete(
                Self.payload(kind),
                invocationID: id,
                checkAccess: { Issue.record("Finished request checked access") },
                context: context,
                retire: {}
            )
        )
        #expect(context.outputs.map(\.kind) == [kind] && context.cancellations.isEmpty && checks == 1 && retired == 1)
    }

    @Test(
        arguments: [
            AutoFillCancellationReason.userCanceled,
            .userInteractionRequired,
            .credentialIdentityNotFound,
            .failed,
        ]
    )
    func cancellationWinsOnceEvenIfPayloadArrivesAfterward(_ reason: AutoFillCancellationReason) throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        var retired = 0
        #expect(completion.cancel(reason, invocationID: id, context: context, retire: { retired += 1 }))
        #expect(!completion.cancel(.failed, invocationID: id, context: context, retire: { retired += 1 }))
        #expect(
            try !completion.complete(
                Self.payload(.password),
                invocationID: id,
                checkAccess: { Issue.record("Retired request checked access") },
                context: context,
                retire: {}
            )
        )
        #expect(context.cancellations == [reason] && context.outputs.isEmpty && retired == 1)
    }

    @Test
    func replacedInvocationCannotCompleteCancelOrReleaseSuccessorBusyGate() throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), old = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle), current = lifecycle.begin()
        #expect(lifecycle.beginAction(current))
        lifecycle.endAction(old)
        #expect(!lifecycle.beginAction(current))
        #expect(
            !completion.cancel(
                .failed,
                invocationID: old,
                context: context,
                retire: { Issue.record("Old cleanup touched successor") }
            )
        )
        #expect(
            try !completion.complete(
                Self.payload(.password),
                invocationID: old,
                checkAccess: { Issue.record("Old output checked successor access") },
                context: context,
                retire: {}
            )
        )
        #expect(
            try completion.complete(
                Self.payload(.password),
                invocationID: current,
                checkAccess: {},
                context: context,
                retire: {}
            )
        )
        #expect(context.outputs.count == 1 && context.cancellations.isEmpty)
    }

    @Test
    func accessCheckReplacingInvocationCannotDispatchOldOutput() throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        #expect(try !completion.complete(
            Self.payload(.password),
            invocationID: id,
            checkAccess: { _ = lifecycle.begin() },
            context: context,
            retire: { Issue.record("Retired newer invocation") }
        ))
        #expect(context.outputs.isEmpty && context.cancellations.isEmpty)
    }

    @Test(arguments: [false, true])
    func synchronousContextReentryCannotRetireNewInvocation(_ cancel: Bool) throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), old = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        var newID: UUID?
        let start: () -> Void = { newID = lifecycle.begin() }
        context.onComplete = start; context.onCancel = start
        if cancel { #expect(
            completion.cancel(
                .userCanceled,
                invocationID: old,
                context: context,
                retire: { Issue.record("Old cancel retired successor") }
            )
        ) } else { #expect(
            try completion.complete(
                Self.payload(.password),
                invocationID: old,
                checkAccess: {},
                context: context,
                retire: { Issue.record("Old completion retired successor") }
            )
        ) }
        let current = try #require(newID)
        #expect(lifecycle.isActive(current) && !lifecycle.isCurrent(old))
        context.onComplete = nil; context.onCancel = nil
        #expect(completion.cancel(.failed, invocationID: current, context: context, retire: {}))
    }

    @Test
    func revokedAuthorizationNeverDispatchesAndAllowsOneTypedCancel() throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        #expect(throws: CancellationError.self) {
            try completion.complete(
                Self.payload(.password),
                invocationID: id,
                checkAccess: { throw CancellationError() },
                context: context,
                retire: { Issue.record("Failed completion retired request") }
            )
        }
        #expect(context.outputs.isEmpty && lifecycle.isActive(id))
        #expect(completion.cancel(.userInteractionRequired, invocationID: id, context: context, retire: {}))
        #expect(context.cancellations == [.userInteractionRequired])
    }

    @Test
    func unsupportedPlatformCapabilityNeverConsumesCompletionBeforeCancel() throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin()
        context.unsupported = .oneTimeCode
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        #expect(throws: AutoFillCompletionError.unsupportedRequest) {
            try completion.complete(
                Self.payload(.oneTimeCode),
                invocationID: id,
                checkAccess: {},
                context: context,
                retire: {}
            )
        }
        #expect(lifecycle.isActive(id) && context.outputs.isEmpty)
        #expect(completion.cancel(.failed, invocationID: id, context: context, retire: {}))
    }

    @Test(arguments: ["password", "code", "rp", "hash", "id", "signature", "authenticator", "attestation"])
    func malformedOutputIsRejectedBeforeClaimOrOSCall(_ field: String) throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle), bytes = Foundation.Data([1])
        let payload: AutoFillCompletion
        if field == "password" { payload = .password(AutoFillPassword(username: "", password: "")) }
        else if field == "code" { payload = .oneTimeCode(TimeBasedOneTimeCode(code: "", period: 30, generatedAt: Date())) }
        else if field == "attestation" { payload = .passkeyRegistration(
            relyingPartyIdentifier: "example.com",
            clientDataHash: bytes,
            credentialID: bytes,
            attestationObject: Foundation.Data()
        ) } else {
            payload = .passkeyAssertion(
                relyingPartyIdentifier: field == "rp" ? "" : "example.com",
                clientDataHash: field == "hash" ? Foundation.Data() : bytes,
                credential: PasskeyAssertionPayload(
                    userHandle: Foundation.Data(),
                    signature: field == "signature" ? Foundation.Data() : bytes,
                    authenticatorData: field == "authenticator" ? Foundation.Data() : bytes,
                    credentialID: field == "id" ? Foundation.Data() : bytes
                )
            )
        }
        if field == "code" {
            #expect(throws: TimeBasedOneTimeCodeError.invalidMetadata) { try completion.complete(
                payload,
                invocationID: id,
                checkAccess: {},
                context: context,
                retire: {}
            ) }
        } else {
            #expect(throws: AutoFillCompletionError.malformedCredential) { try completion.complete(
                payload,
                invocationID: id,
                checkAccess: {},
                context: context,
                retire: {}
            ) }
        }
        #expect(lifecycle.isActive(id) && context.outputs.isEmpty && context.cancellations.isEmpty)
    }

    @Test
    func cancelledConsumerCannotDispatchResolvedPayloadButCanStillCancelContext() async throws {
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin(), gate = AuthOperationTestGate(
        )
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        let task = Task { @MainActor in
            await gate.pause()
            return try completion.complete(
                Self.payload(.password),
                invocationID: id,
                checkAccess: { Issue.record("Cancelled consumer checked lease") },
                context: context,
                retire: {}
            )
        }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(context.outputs.isEmpty)
        #expect(completion.cancel(.userCanceled, invocationID: id, context: context, retire: {}))
    }

    @Test(arguments: [AutoFillCompletionKind.password, .oneTimeCode, .passkeyAssertion, .passkeyRegistration])
    func outputDiagnosticsAreRedactedAndBoundaryRetainsNoPayloadOrContext(_ kind: AutoFillCompletionKind) throws {
        let value = Self.payload(kind)
        #expect(
            String(describing: value) == "AutoFillCompletion(<redacted>)" && String(reflecting: value) == "AutoFillCompletion(<redacted>)"
        )
        let lifecycle = ExtensionRequestLifecycle(), completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        #expect(Mirror(reflecting: completion).children.map(\.label) == ["lifecycle", "now"])
    }

    static func payload(_ kind: AutoFillCompletionKind) -> AutoFillCompletion {
        let bytes = Foundation.Data([1])
        switch kind {
        case .password: return .password(AutoFillPassword(username: "", password: "synthetic-password"))
        case .oneTimeCode: return .oneTimeCode(TimeBasedOneTimeCode(code: "123456", period: .max, generatedAt: Date()))
        case .passkeyAssertion: return .passkeyAssertion(
                relyingPartyIdentifier: "example.com",
                clientDataHash: bytes,
                credential: PasskeyAssertionPayload(
                    userHandle: Foundation.Data(),
                    signature: bytes,
                    authenticatorData: bytes,
                    credentialID: bytes
                )
            )
        case .passkeyRegistration: return .passkeyRegistration(
                relyingPartyIdentifier: "example.com",
                clientDataHash: bytes,
                credentialID: bytes,
                attestationObject: bytes
            )
        }
    }
}

/// Synthetic outputs retained only for assertions, never a production picker/model store.
@MainActor final class AutoFillContextFixture: AutoFillExtensionContext {
    var outputs: [AutoFillCompletion] = []
    var cancellations: [AutoFillCancellationReason] = []
    var unsupported: AutoFillCompletionKind?
    var onComplete: (() -> Void)?, onCancel: (() -> Void)?
    func supports(_ kind: AutoFillCompletionKind) -> Bool { kind != unsupported }
    func complete(_ credential: AutoFillCompletion) { outputs.append(credential); onComplete?() }
    func cancel(_ reason: AutoFillCancellationReason) { cancellations.append(reason); onCancel?() }
}
