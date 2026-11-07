import Domain
import SwiftUI

struct PasskeyRecoveryReviewView: View {
    let model: VaultModel
    let review: PasskeyRegistrationRecoveryReview
    @State private var acknowledged = false

    var body: some View {
        ScrollView {
            content
                .padding()
        }
        .frame(idealWidth: 500, idealHeight: 520)
        .interactiveDismissDisabled(model.state.isPasskeyRecoveryBusy)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Unresolved Credential Save").font(.headline)
            Text(review.relyingPartyIdentifier).textSelection(.enabled)
            Text(review.serverConfirmed ? "The server confirmed the write, but local recovery is unresolved." :
                "We do not know whether the server accepted the write. A request already sent may still finish.")
            Text(
                "First inspect this service and the vault in an official client. Abandoning tracking removes only this local recovery marker. It does not delete a credential, undo a server write, or prove that saving again is safe."
            )
            switch review.readiness {
            case .ready:
                Toggle(
                    "I inspected the credential and accept the unresolved outcome and risk of a duplicate if I save again.",
                    isOn: $acknowledged
                )
                Button("Abandon Local Tracking", role: .destructive) {
                    Task { await model.perform(.abandonPasskeyRegistrationRecovery(review)) }
                }
                .disabled(
                    !acknowledged || model.state.isPasskeyRecoveryBusy || model.state.passkeyRecoveryReview != review
                )
            case .requiresFreshUnlock:
                Text(
                    "Lock and unlock the app, then complete a full sync and review again. The originating unlock must be revoked first."
                )
            case .legacyOriginUnknown:
                Text(
                    "This older record has no originating unlock. It stays blocked; this screen cannot safely abandon it. Full sync can still resolve it if the exact credential is found."
                )
            }
            Button("Keep Tracking / Close") { model.send(.passkeyRecoveryReviewDismissed) }
                .disabled(model.state.isPasskeyRecoveryBusy)
        }
    }
}
