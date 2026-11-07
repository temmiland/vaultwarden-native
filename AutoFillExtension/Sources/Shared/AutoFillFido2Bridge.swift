import AutoFillData
import BitwardenSDKAdapter
import PlatformServices

/// Invocation-scoped composition only. SDK protocols/models stay in BitwardenSDKAdapter;
/// platform device-owner verification is supplied through its Domain port.
enum AutoFillFido2Bridge {
    static func store(
        views: [SDKAutoFillCredentialView],
        session: ExtensionVaultSession,
        save: (@Sendable (SDKAutoFillEncryptedCipher) async throws -> Void)? = nil
    ) -> SDKAutoFillFidoCredentialStore {
        SDKAutoFillFidoCredentialStore(
            views: views,
            userID: session.accountInfo.userId,
            readAccess: { _ = try session.readCache() },
            checkAccess: { try session.checkAccess() },
            metadata: { view in try session.perform { try $0.passkeyMetadata(in: view) } },
            save: save
        )
    }

    static func userInterface(
        session: ExtensionVaultSession,
        relyingPartyIdentifier: String,
        selected: SDKAutoFillCredentialView? = nil,
        target: SDKAutoFillCredentialView? = nil
    ) -> SDKAutoFillFidoUserInterface {
        SDKAutoFillFidoUserInterface(
            selectedForAuthentication: selected,
            targetForCreation: target,
            relyingPartyIdentifier: relyingPartyIdentifier,
            readAccess: { _ = try session.readCache() },
            checkAccess: { try session.checkAccess() },
            requireCurrent: { view, editing in try session.requireCurrentAccess(to: view, forEditing: editing) },
            verification: SystemPasskeyUserVerifier()
        )
    }
}
