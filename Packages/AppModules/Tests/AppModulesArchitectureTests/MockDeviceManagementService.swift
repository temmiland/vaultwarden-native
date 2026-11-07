import Domain
import Foundation
@testable import SettingsPresentation

final class MockDeviceManagementService: SettingsRepository, @unchecked Sendable {
    var devicesToReturn: [RegisteredDevice] = []
    var fetchErrorToThrow: Error?
    var revokeErrorToThrow: Error?
    var revocationGate: MockDeviceRevocationGate?
    private var fetchResponses: [MockDeviceFetchResponse] = []
    private(set) var revokedIDs: [String] = []
    private(set) var fetchCallCount = 0
    private(set) var revokeCallCount = 0

    func enqueueFetch(devices: [RegisteredDevice], gate: MockDeviceFetchGate? = nil) {
        fetchResponses.append(MockDeviceFetchResponse(devices: devices, gate: gate))
    }

    func enqueueFetchFailure(_ error: Error, gate: MockDeviceFetchGate? = nil) {
        fetchResponses.append(MockDeviceFetchResponse(error: error, gate: gate))
    }

    func fetchDevices() async throws -> [RegisteredDevice] {
        fetchCallCount += 1
        let response = fetchResponses.isEmpty
            ? MockDeviceFetchResponse(devices: devicesToReturn, error: fetchErrorToThrow)
            : fetchResponses.removeFirst()
        if let gate = response.gate { await gate.pause() }
        if let error = response.error { throw error }
        return response.devices
    }

    func revokeDevice(id: String) async throws {
        revokeCallCount += 1
        if let revocationGate { await revocationGate.pause() }
        if let revokeErrorToThrow { throw revokeErrorToThrow }
        revokedIDs.append(id)
    }
}

private struct MockDeviceFetchResponse {
    var devices: [RegisteredDevice] = []
    var error: Error?
    var gate: MockDeviceFetchGate?
}

struct MockDeviceManagementError: Error {}

actor MockDeviceRevocationGate {
    private var isPaused = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isPaused = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    func waitUntilPaused() async {
        if isPaused { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

actor MockDeviceFetchGate {
    private var isPaused = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isPaused = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    func waitUntilPaused() async {
        if isPaused { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
