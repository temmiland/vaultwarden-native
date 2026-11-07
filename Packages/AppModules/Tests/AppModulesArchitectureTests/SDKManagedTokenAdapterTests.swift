import BitwardenSDKAdapter
import Testing

@Suite
struct SDKManagedTokenAdapterTests {
    @Test
    func delegatesTokenOwnershipWithoutRetainingASecondAuthority() async {
        let calls = AuthInvocationProbe()
        let adapter = SDKManagedTokenAdapter { await calls.record(); return "fixture-access" }
        #expect(await adapter.getAccessToken() == "fixture-access")
        #expect(await calls.count == 1)
    }

    @Test
    func cancelledCallerNeverInvokesTheTokenCapability() async {
        let gate = AuthOperationTestGate()
        let calls = AuthInvocationProbe()
        let adapter = SDKManagedTokenAdapter { await calls.record(); return "fixture-access" }
        let task = Task { await gate.pause(); return await adapter.getAccessToken() }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        #expect(await task.value == nil)
        #expect(await calls.count == 0)
    }

    @Test
    func cancelledNoncooperativeLookupCannotReturnALateToken() async {
        let gate = AuthOperationTestGate()
        let adapter = SDKManagedTokenAdapter { await gate.pause(); return "fixture-late-access" }
        let task = Task { await adapter.getAccessToken() }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        #expect(await task.value == nil)
    }
}
