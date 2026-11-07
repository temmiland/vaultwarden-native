import BitwardenSDKAdapter
import Domain
import Foundation

/// Request body for `POST {identityURL}/accounts/prelogin`. Field name confirmed against the
/// vendored `bitwarden-api-identity` Rust model (`PasswordPreloginRequestModel`, serde-renamed to
/// lowercase `email`).
struct PreloginRequestBody: Codable {
    let email: String
}

/// Response body for the prelogin endpoint. Field names confirmed against
/// `PasswordPreloginResponseModel` in the vendored `bitwarden-api-identity` crate (camelCase is the
/// primary/serializing form there).
struct PreloginResponseBody: Decodable {
    let kdf: Int?
    let kdfIterations: Int?
    let kdfMemory: Int?
    let kdfParallelism: Int?

    /// Keep omitted-field defaults, but reject invalid or unknown values before SDK conversion.
    var resolvedParameters: KeyDerivationParameters {
        get throws {
            try SDKKeyDerivationMapper.parameters(
                type: kdf,
                iterations: kdfIterations,
                memory: kdfMemory,
                parallelism: kdfParallelism
            )
        }
    }
}
