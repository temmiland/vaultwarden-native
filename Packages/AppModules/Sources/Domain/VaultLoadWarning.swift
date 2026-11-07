/// Privacy-safe degradation metadata. No item names, encrypted payloads, keys or SDK diagnostic
/// strings cross the presentation boundary with a warning.
public enum VaultLoadWarning: Equatable, Sendable {
    case passkeyRegistrationRecoveryPending
    case unavailableItems(count: Int)
}
