@testable import AuthPresentation
import Domain

@MainActor
final class MockDeviceNameClient: DeviceNameClient {
    var name = "Test Device"

    func currentDeviceName() -> String { name }
}
