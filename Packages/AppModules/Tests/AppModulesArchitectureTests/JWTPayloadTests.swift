@testable import Data
import Foundation
import Testing

@Suite
struct JWTPayloadTests {
    /// Builds a syntactically valid (unsigned) JWT with the given payload, matching the shape a
    /// real Bitwarden/Vaultwarden access token has: header.payload.signature.
    private func makeToken(payload: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"])
        let body = try! JSONSerialization.data(withJSONObject: payload)
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(base64URL(header)).\(base64URL(body)).signature"
    }

    @Test
    func subjectIsExtractedFromValidToken() {
        let token = makeToken(payload: ["sub": "user-id-123", "email": "user@example.com"])

        #expect(JWTPayload.subject(from: token) == "user-id-123")
    }

    @Test
    func subjectIsNilForMalformedToken() {
        #expect(JWTPayload.subject(from: "not-a-jwt") == nil)
        #expect(JWTPayload.subject(from: "") == nil)
    }

    @Test
    func subjectIsNilWhenSubClaimMissing() {
        let token = makeToken(payload: ["email": "user@example.com"])

        #expect(JWTPayload.subject(from: token) == nil)
    }
}
