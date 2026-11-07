import AutoFillContract
import Foundation

public struct AutoFillCredentialList: Sendable {
    public let items: [AutoFillLoginSummary]
    /// Eligible items that could not be safely mapped/decrypted; policy-excluded items do not count.
    public let unavailableItemCount: Int
    /// URI evaluation reached its shared time budget, so additional matching items may be missing.
    public let matchingEvaluationIncomplete: Bool
    public var warningMessage: String? {
        var warnings: [String] = []
        if unavailableItemCount > 0 {
            warnings.append(
                "Some saved items couldn't be read safely. Open Vaultwarden and sync before relying on this list."
            )
        }
        if matchingEvaluationIncomplete {
            warnings.append(
                "AutoFill stopped matching at its time limit. Some matching logins may be missing; try again or open Vaultwarden."
            )
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }

    public init(
        items: [AutoFillLoginSummary],
        unavailableItemCount: Int,
        matchingEvaluationIncomplete: Bool = false
    ) {
        self.items = items
        self.unavailableItemCount = unavailableItemCount
        self.matchingEvaluationIncomplete = matchingEvaluationIncomplete
    }
}

public struct AutoFillPassword: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let username: String
    public let password: String
    public init(username: String, password: String) { self.username = username; self.password = password }
    public var description: String { "AutoFillPassword(<redacted>)" }
    public var debugDescription: String { description }
}

public enum AutoFillOperationError: Error, Sendable {
    case noSharedKey, noAccountInfo, keychainUnavailable, noCache, decryptFailed, accessDenied
    case saveFailed, notAuthenticated, operationInProgress
}

/// Platform-neutral assertion output; the extension alone maps this to AuthenticationServices.
public struct PasskeyAssertionPayload: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let userHandle: Foundation.Data
    public let signature: Foundation.Data
    public let authenticatorData: Foundation.Data
    public let credentialID: Foundation.Data
    public var description: String { "PasskeyAssertionPayload(<redacted>)" }
    public var debugDescription: String { description }
    public init(
        userHandle: Foundation.Data,
        signature: Foundation.Data,
        authenticatorData: Foundation.Data,
        credentialID: Foundation.Data
    ) {
        self.userHandle = userHandle; self.signature = signature
        self.authenticatorData = authenticatorData; self.credentialID = credentialID
    }
}
