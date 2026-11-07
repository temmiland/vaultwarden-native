import BitwardenSdk
import Domain

/// Existing AutoFill registration scaffolding, using the same Domain draft and SDK reconstruction
/// as the app editor. The SDK attaches the credential during registration.
public enum PasskeyItemFactory {
    public static func makeLoginCipherView(
        relyingPartyIdentifier: String,
        userName: String?
    ) -> CipherView {
        var draft = VaultItemDraft(kind: .login)
        draft.name = relyingPartyIdentifier
        draft.username = userName ?? ""
        draft.uris = ["https://\(relyingPartyIdentifier)"]
        do {
            return try SDKVaultItemDraftMapper.applying(draft, to: nil)
        } catch {
            preconditionFailure("A new login cipher must remain losslessly editable.")
        }
    }
}
