import Domain
import Foundation

/// Enforces the app-wide timeout preference while the app is not frontmost. AppFeature owns the
/// lifecycle clock; SettingsFeature only edits the preference through its Domain repository port.
@MainActor
public final class VaultTimeoutWatchdog {
    public enum PendingAction: Equatable {
        case lock
        case logOut
    }

    private let preference: () throws -> VaultTimeoutPreference
    private let now: () -> ContinuousClock.Instant
    private var inactiveSince: ContinuousClock.Instant?

    public init(
        preference: @escaping () throws -> VaultTimeoutPreference = { .default },
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.preference = preference
        self.now = now
    }

    /// Repeated inactive notifications keep the first timestamp so scene-phase flapping cannot
    /// continually postpone the deadline.
    public func noteBecameInactive() {
        guard inactiveSince == nil else { return }
        inactiveSince = now()
    }

    public func noteBecameActive() { inactiveSince = nil }

    public func pendingAction() throws -> PendingAction? {
        guard let inactiveSince else { return nil }
        let preference = try preference()
        guard
            let threshold = preference.duration.seconds,
            inactiveSince.duration(to: now()) >= .seconds(Int64(threshold))
        else { return nil }

        switch preference.action {
        case .lock: return .lock
        case .logOut: return .logOut
        }
    }
}
