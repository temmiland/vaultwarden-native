import AutoFillData
import Foundation
import Testing

@Suite @MainActor
struct AutoFillContextQueryIntegrationTests {
    @Test
    func failedIdentifiedPasswordDoesNotBrowseOrCompleteAnotherCipher() async throws {
        let source = AutoFillQuerySourceFixture(ids: ["selected", "other"]), lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(
        )
        source.setView(AutoFillQuerySourceFixture.view(id: "selected", password: nil), id: "selected")
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle), id = lifecycle.begin()
        do {
            let password = try await CredentialQuery(source: source).password(cipherId: "selected")
            try completion.complete(
                .password(password),
                invocationID: id,
                checkAccess: { _ = try source.readCache() },
                context: context,
                retire: {}
            )
        } catch { completion.cancel(
            AutoFillRequestErrorPolicy.cancellation(for: error, route: .identifiedCredential),
            invocationID: id,
            context: context,
            retire: {}
        ) }
        #expect(
            source.decryptedIDs == ["selected"] && context.outputs.isEmpty && context.cancellations == [
                .credentialIdentityNotFound,
            ]
        )
    }

    @Test
    func lockAfterPasswordResolutionBeforeTerminalDispatchCancelsInsteadOfFilling() async throws {
        let source = AutoFillQuerySourceFixture(), lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(
        ), id = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle), password = try await CredentialQuery(
            source: source
        ).password(cipherId: "cipher-1")
        source.deny()
        do { try completion.complete(
            .password(password),
            invocationID: id,
            checkAccess: { _ = try source.readCache() },
            context: context,
            retire: {}
        ) } catch { completion.cancel(
            AutoFillRequestErrorPolicy.cancellation(for: error, route: .identifiedCredential),
            invocationID: id,
            context: context,
            retire: {}
        ) }
        #expect(context.outputs.isEmpty && context.cancellations == [.userInteractionRequired])
    }

    @Test
    func TOTPIsGeneratedAtSelectionAndPassedToContextWithoutPickerSeedOrCachedCode() async throws {
        let source = AutoFillQuerySourceFixture(), query = CredentialQuery(source: source)
        source.setCodePeriod(.max) // expiry behavior is tested with an injected clock in AutoFillTOTPExpiryTests
        let list = try await query.logins(requiringTOTP: true)
        #expect(source.seeds.isEmpty)
        let selected = try #require(list.items.first)
        source.setView(AutoFillQuerySourceFixture.view(seed: "fresh-selection-seed"))
        let code = try await query.oneTimeCode(cipherId: selected.cipherId)
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), id = lifecycle.begin()
        try AutoFillRequestCompletion(lifecycle: lifecycle).complete(
            .oneTimeCode(code),
            invocationID: id,
            checkAccess: { _ = try source.readCache() },
            context: context,
            retire: {}
        )
        #expect(source.seeds == ["fresh-selection-seed"] && context.outputs.count == 1)
        guard case let .oneTimeCode(value) = context.outputs.first else { Issue.record("Expected code output"); return }
        #expect(value.code == "123456") // fake generator, not SDK crypto
    }

    @Test
    func lateQueryResultAfterNewInvocationCannotReachSharedContext() async throws {
        let gate = AuthOperationTestGate()
        let source = AutoFillQuerySourceFixture(gate: gate)
        let lifecycle = ExtensionRequestLifecycle(), context = AutoFillContextFixture(), old = lifecycle.begin()
        let completion = AutoFillRequestCompletion(lifecycle: lifecycle)
        let task = Task { @MainActor in
            let password = try await CredentialQuery(source: source).password(cipherId: "cipher-1")
            return try completion.complete(
                .password(password),
                invocationID: old,
                checkAccess: { Issue.record("Old result checked successor lease") },
                context: context,
                retire: {}
            )
        }
        await gate.waitUntilPaused()
        let current = lifecycle.begin()
        await gate.release()
        #expect(try await !task.value && context.outputs.isEmpty)
        #expect(completion.cancel(.userCanceled, invocationID: current, context: context, retire: {}))
    }
}
