import Foundation

/// Builds the `application/x-www-form-urlencoded` body for `POST {identityURL}/connect/token`.
/// This is a standard OAuth2 token endpoint (IdentityServer-derived), not part of the OpenAPI-
/// documented REST API, so it isn't JSON - field names match Bitwarden's official clients
/// (`client_id=connector`, `scope=api offline_access`, etc).
enum TokenRequestBuilder {
    static func passwordGrant(
        username: String,
        passwordHash: String,
        device: DeviceInfo,
        twoFactor: TwoFactorSubmission?
    ) -> Data {
        var items = commonItems(device: device)
        items.append(URLQueryItem(name: "grant_type", value: "password"))
        items.append(URLQueryItem(name: "username", value: username))
        items.append(URLQueryItem(name: "password", value: passwordHash))
        if let twoFactor {
            items.append(URLQueryItem(name: "twoFactorToken", value: twoFactor.code))
            items.append(URLQueryItem(name: "twoFactorProvider", value: String(twoFactor.provider)))
            items.append(URLQueryItem(name: "twoFactorRemember", value: twoFactor.remember ? "1" : "0"))
        }
        return OAuthClientConfiguration.formBody(items)
    }

    private static func commonItems(device: DeviceInfo) -> [URLQueryItem] {
        [
            URLQueryItem(name: "scope", value: "api offline_access"),
            URLQueryItem(name: "client_id", value: OAuthClientConfiguration.clientID),
            URLQueryItem(name: "deviceIdentifier", value: device.identifier),
            URLQueryItem(name: "deviceName", value: device.name),
            URLQueryItem(name: "deviceType", value: String(device.typeCode)),
        ]
    }
}

/// A previously-selected two-factor code to submit alongside a password grant.
public struct TwoFactorSubmission: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let code: String
    public let provider: Int
    public let remember: Bool

    public init(code: String, provider: Int, remember: Bool) {
        self.code = code; self.provider = provider; self.remember = remember
    }

    public var description: String { "TwoFactorSubmission(<redacted>)" }
    public var debugDescription: String { description }
}

/// Successful `connect/token` response. Field names confirmed against the reference Bitwarden iOS
/// client's `IdentityTokenResponseModel` / `IdentityTokenRefreshResponseModel`; decoded via
/// `FlexibleKeyDecoding` since the server mixes snake_case OAuth fields with PascalCase Bitwarden
/// fields.
public struct TokenSuccessResponse: Decodable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let expiresIn: Int
    public let tokenType: String
    public let refreshToken: String?
    public let key: String?
    public let privateKey: String?
    public let kdf: Int?
    public let kdfIterations: Int?
    public let kdfMemory: Int?
    public let kdfParallelism: Int?

    public var description: String { "TokenSuccessResponse(<redacted>)" }
    public var debugDescription: String { description }
}

/// Error body for a failed `connect/token` request. When `twoFactorProviders` is present (even if
/// the underlying OAuth `error` is `invalid_grant`), the request didn't actually fail - the server
/// is asking for a second factor.
///
/// Vaultwarden encodes `TwoFactorProviders` as an array of *string* numbers (`["0"]`), not JSON
/// integers like the official Bitwarden server's OpenAPI spec suggests - decode leniently for both.
struct TokenErrorResponse: Decodable, Sendable {
    let error: String?
    let errorDescription: String?
    let twoFactorProviders: [Int]?

    private enum CodingKeys: String, CodingKey {
        case error, errorDescription, twoFactorProviders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)

        if let ints = try? container.decodeIfPresent([Int].self, forKey: .twoFactorProviders) {
            twoFactorProviders = ints
        } else if let strings = try? container.decodeIfPresent([String].self, forKey: .twoFactorProviders) {
            twoFactorProviders = strings.compactMap(Int.init)
        } else {
            twoFactorProviders = nil
        }
    }
}

/// The outcome of a `connect/token` request, covering the three shapes the server can return.
public enum TokenRequestOutcome: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case success(TokenSuccessResponse)
    case twoFactorRequired(providers: [Int])
    case failure(message: String)

    public var description: String { "TokenRequestOutcome(<redacted>)" }
    public var debugDescription: String { description }
}
