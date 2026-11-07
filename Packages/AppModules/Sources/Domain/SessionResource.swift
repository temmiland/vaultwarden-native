/// The runtime owns a revocable resource, not a public crypto client. Revocation is permanent;
/// a subsequent unlock creates a new resource and runtime identity.
public protocol SessionResource: Sendable {
    var isActive: Bool { get }
    func revoke()
}

public enum SessionRevocationReason: Sendable, Equatable {
    case lock, logout, expired
}
