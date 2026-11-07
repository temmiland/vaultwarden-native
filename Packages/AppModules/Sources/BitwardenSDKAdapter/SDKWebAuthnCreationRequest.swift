import Foundation

/// Existing request envelope, independent of AuthenticationServices. The platform's client-data
/// hash is supplied separately; this structurally required placeholder challenge is not hashed.
public enum SDKWebAuthnCreationRequest {
    private struct RP: Encodable { let id: String; let name: String }
    private struct User: Encodable { let id: String; let name: String; let displayName: String }
    private struct Parameter: Encodable { let type = "public-key"; let alg: Int }
    private struct Selection: Encodable { let residentKey = "required"; let requireResidentKey = true; let userVerification: String }
    private struct PublicKey: Encodable {
        let challenge: String; let rp: RP; let user: User; let pubKeyCredParams: [Parameter]
        let authenticatorSelection: Selection; let attestation = "none"
    }

    private struct Envelope: Encodable { let publicKey: PublicKey }
    public static func make(
        relyingPartyIdentifier: String,
        userName: String,
        userHandle: Foundation.Data,
        supportedAlgorithms: [Int],
        userVerification: String
    ) throws -> String {
        guard !relyingPartyIdentifier.isEmpty, ["required", "preferred", "discouraged"].contains(userVerification) else {
            throw SDKAutoFillFidoError.invalidRequest
        }
        let algorithms = supportedAlgorithms.isEmpty ? [-7] : supportedAlgorithms
        let request = PublicKey(
            challenge: base64URL(Foundation.Data([0])),
            rp: RP(id: relyingPartyIdentifier, name: relyingPartyIdentifier),
            user: User(id: base64URL(userHandle), name: userName, displayName: userName),
            pubKeyCredParams: algorithms.map { Parameter(alg: $0) },
            authenticatorSelection: Selection(userVerification: userVerification)
        )
        return String(decoding: try JSONEncoder().encode(Envelope(publicKey: request)), as: UTF8.self)
    }

    private static func base64URL(_ value: Foundation.Data) -> String {
        value.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
