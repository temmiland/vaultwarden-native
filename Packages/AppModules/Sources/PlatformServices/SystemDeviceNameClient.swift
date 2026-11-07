import Domain
import Foundation

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Apple-platform adapter for the name included in identity-token requests.
@MainActor
public final class SystemDeviceNameClient: DeviceNameClient {
    public init() {}

    public func currentDeviceName() -> String {
        #if os(iOS)
            UIDevice.current.name
        #else
            Host.current().localizedName ?? "Mac"
        #endif
    }
}
