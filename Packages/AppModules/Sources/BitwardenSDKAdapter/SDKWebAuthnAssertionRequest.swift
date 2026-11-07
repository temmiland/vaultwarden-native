import Foundation

/// SDK request encoding only; OS clientDataHash is supplied separately to the authenticator.
public enum SDKWebAuthnAssertionRequest {
    private struct AllowedCredential: Encodable { let type = "public-key"; let id: String }
    private struct PublicKey: Encodable {
        let challenge: String
        let rpId: String
        let allowCredentials: [AllowedCredential]
        let userVerification: String
    }

    private struct Envelope: Encodable { let publicKey: PublicKey }
    public static func make(
        relyingPartyIdentifier: String,
        credentialID: Foundation.Data,
        userVerification: String = "preferred"
    ) throws -> String {
        guard ["required", "preferred", "discouraged"].contains(userVerification) else {
            throw SDKAutoFillFidoError.accessDenied
        }
        let envelope = Envelope(publicKey: PublicKey(
            challenge: base64URL(Foundation.Data([0])),
            rpId: relyingPartyIdentifier,
            allowCredentials: [AllowedCredential(id: base64URL(credentialID))],
            userVerification: userVerification
        ))
        return String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    }

    private static func base64URL(_ data: Foundation.Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
