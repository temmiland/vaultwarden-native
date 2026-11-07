import Foundation

public enum PasskeyRecoveryReviewReadiness: Sendable, Equatable {
    case ready, requiresFreshUnlock, legacyOriginUnknown
}

/// Metadata-only, session/revision-bound review. It is an acknowledgment of uncertainty, never
/// evidence of rejection, rollback, or permission to automatically retry a server write.
public struct PasskeyRegistrationRecoveryReview: Sendable, Equatable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: UUID
    public let vaultRevision: UInt64
    public let relyingPartyIdentifier: String
    public let serverConfirmed: Bool
    public let readiness: PasskeyRecoveryReviewReadiness
    public init(
        id: UUID = UUID(),
        vaultRevision: UInt64,
        relyingPartyIdentifier: String,
        serverConfirmed: Bool,
        readiness: PasskeyRecoveryReviewReadiness
    ) {
        self.id = id; self.vaultRevision = vaultRevision; self.relyingPartyIdentifier = relyingPartyIdentifier
        self.serverConfirmed = serverConfirmed; self.readiness = readiness
    }

    public var description: String { "PasskeyRegistrationRecoveryReview(<redacted>)" }
    public var debugDescription: String { description }
}

public enum PasskeyRegistrationReviewError: Error, Sendable, Equatable {
    case unavailable, syncRequired, reviewChanged, freshUnlockRequired, legacyOriginUnknown
}
