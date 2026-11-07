import Foundation

/// Minimal, dependency-free decoder for the payload segment of a JWT access token. Bitwarden's
/// identity server encodes the user id in the standard `sub` claim; clients read it directly from
/// the token rather than requiring a separate profile round-trip. This never validates the
/// signature (the token was just received over TLS from the server we requested it from) - it's
/// only used to extract non-secret claims like `sub`/`email` for local bookkeeping.
enum JWTPayload {
    static func decode(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        guard let data = base64URLDecode(String(segments[1])) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Extracts the `sub` claim (the user id) from an access token.
    static func subject(from token: String) -> String? {
        decode(token)?["sub"] as? String
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: paddingLength))
        return Data(base64Encoded: base64)
    }
}
