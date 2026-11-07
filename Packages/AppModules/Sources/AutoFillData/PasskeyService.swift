import AutoFillContract
import BitwardenSDKAdapter
import Foundation

/// Existing passkey query/assertion use cases, independent of OS controllers and SDK UI prompts.
/// Registration's server writer remains a separate migration; this actor adds no compatibility.
public actor PasskeyService {
    public typealias Authenticate = @Sendable (SDKAutoFillCredentialView, String) async throws -> PasskeyAssertionPayload
    private let source: any AutoFillCredentialSource
    private let credentials: CredentialQuery
    private var isAsserting = false
    public init(source: any AutoFillCredentialSource, credentials: CredentialQuery) {
        self.source = source; self.credentials = credentials
    }

    public func matching(relyingPartyIdentifier: String, allowedCredentials: [Data] = []) async throws -> AutoFillCredentialList {
        let snapshot = AutoFillCredentialSnapshot(cache: try source.readCache())
        var items: [AutoFillLoginSummary] = [], failures = 0
        var views: [SDKAutoFillCredentialView] = []
        for dto in snapshot.cache.ciphers {
            try Task.checkCancellation()
            guard SDKVaultAccessPolicy.isEligibleForAutoFill(dto) else { continue }
            guard let id = dto.id, snapshot.uniqueCipher(id: id) != nil else { failures += 1; continue }
            do {
                let view = try await source.decrypt(dto)
                try Task.checkCancellation()
                try CredentialQuery.requireCurrentAccess(to: view, matching: dto, source: source)
                guard view.id == id else { throw AutoFillOperationError.accessDenied }
                guard view.hasPasskeys else { continue }
                let passkeys = try source.passkeys(in: view)
                try CredentialQuery.requireCurrentAccess(to: view, matching: dto, source: source)
                views.append(view)
                let credentialCounts = Dictionary(grouping: passkeys, by: \.credentialId).mapValues(\.count)
                var hasInvalidCredential = false
                for credential in passkeys where credential.rpId == relyingPartyIdentifier {
                    guard credential.cipherId == id, !credential.credentialId.isEmpty,
                          credentialCounts[credential.credentialId] == 1 else { hasInvalidCredential = true; continue }
                    guard allowedCredentials.isEmpty || allowedCredentials.contains(credential.credentialId) else { continue }
                    items.append(AutoFillLoginSummary(
                        cipherId: id,
                        name: view.name,
                        username: credential.userNameForUi,
                        fido2CredentialId: credential.credentialId,
                        fido2UserHandle: credential.userHandle
                    ))
                }
                if hasInvalidCredential { failures += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch { try source.checkAccess(); failures += 1 }
        }
        let currentSnapshot = AutoFillCredentialSnapshot(cache: try source.readCache())
        for view in views {
            try CredentialQuery.requireCurrentAccess(
                to: view,
                matching: view.id.flatMap { currentSnapshot.uniqueCipher(id: $0) },
                source: source
            )
        }
        return AutoFillCredentialList(items: items, unavailableItemCount: failures)
    }

    /// An OS identity already selects one cipher/credential. Never decrypt the whole vault to
    /// resolve it, and never substitute another credential from that cipher after a stale match.
    public func match(cipherId: String, credentialID: Data, relyingPartyIdentifier: String) async throws -> AutoFillLoginSummary {
        guard !credentialID.isEmpty, let view = try await credentials.cipherView(cipherId: cipherId),
              view.hasPasskeys else { throw AutoFillOperationError.decryptFailed }
        let current = try selectedCredential(
            in: view,
            id: credentialID,
            cipherId: cipherId,
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        return AutoFillLoginSummary(
            cipherId: cipherId,
            name: view.name,
            username: current.userNameForUi,
            fido2CredentialId: current.credentialId,
            fido2UserHandle: current.userHandle
        )
    }

    public func assertion(
        for match: AutoFillLoginSummary,
        relyingPartyIdentifier: String,
        allowedCredentials: [Data] = [],
        userVerification: String = "preferred",
        authenticate: Authenticate
    ) async throws -> PasskeyAssertionPayload {
        guard !isAsserting else { throw AutoFillOperationError.operationInProgress }
        isAsserting = true
        defer { isAsserting = false }
        guard let id = match.fido2CredentialId, !id.isEmpty,
              allowedCredentials.isEmpty || allowedCredentials.contains(id),
              let view = try await credentials.cipherView(cipherId: match.cipherId) else { throw AutoFillOperationError.decryptFailed }
        // A retained picker is not authorization. Bind the selected bytes to the exact current RP.
        _ = try selectedCredential(
            in: view,
            id: id,
            cipherId: match.cipherId,
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let request = try SDKWebAuthnAssertionRequest.make(
            relyingPartyIdentifier: relyingPartyIdentifier,
            credentialID: id,
            userVerification: userVerification
        )
        let result = try await authenticate(view, request)
        try Task.checkCancellation()
        try CredentialQuery.requireCurrentAccess(to: view, source: source)
        guard result.credentialID == id else { throw AutoFillOperationError.accessDenied }
        if userVerification == "required" {
            guard result.authenticatorData.count >= 37,
                  result.authenticatorData[result.authenticatorData.startIndex + 32] & 0x04 != 0 else {
                throw AutoFillOperationError.accessDenied
            }
        }
        return result
    }

    private func selectedCredential(
        in view: SDKAutoFillCredentialView,
        id: Data,
        cipherId: String,
        relyingPartyIdentifier: String
    ) throws -> SDKAutoFillPasskeyMetadata {
        let matching = try source.passkeys(in: view).filter { $0.credentialId == id }
        guard matching.count == 1, let current = matching.first,
              current.cipherId == cipherId, current.rpId == relyingPartyIdentifier else {
            throw AutoFillOperationError.accessDenied
        }
        try Task.checkCancellation()
        try CredentialQuery.requireCurrentAccess(to: view, source: source)
        return current
    }
}
