import Foundation

/// One client/form configuration for password/TOTP login and both refresh consumers. No SDK,
/// feature, platform or Keychain dependencies belong in this wire-format helper.
public enum OAuthClientConfiguration {
    public static let clientID = "connector"

    public static func refreshGrantBody(refreshToken: String) -> Foundation.Data {
        formBody([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ])
    }

    public static func formBody(_ items: [URLQueryItem]) -> Foundation.Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = items.map { item -> String in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? (item.value ?? "")
            return "\(name)=\(value)"
        }
        return Foundation.Data(pairs.joined(separator: "&").utf8)
    }
}
