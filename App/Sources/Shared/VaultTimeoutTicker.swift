import Combine
import SwiftUI

/// Drives `AppModel.applyPendingTimeoutAction()` on a slow repeating tick.
///
/// Scene-phase changes alone aren't enough: they fire when the user *comes back*, but a timeout
/// whose whole point is revoking the AutoFill extension's key needs to fire while they're away and
/// possibly never return. 30 seconds is coarse enough to be free and fine enough that the shortest
/// configurable timeout (one minute) is honoured close to the second it's due.
private struct VaultTimeoutTicker: ViewModifier {
    let appModel: VaultwardenAppModel

    private let tick = Timer.publish(every: 30, tolerance: 10, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content.onReceive(tick) { _ in
            Task { await appModel.applyPendingTimeoutAction() }
        }
    }
}

extension View {
    func vaultTimeoutTicker(appModel: VaultwardenAppModel) -> some View {
        modifier(VaultTimeoutTicker(appModel: appModel))
    }
}
