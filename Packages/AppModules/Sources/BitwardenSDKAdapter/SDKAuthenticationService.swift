import BitwardenSdk
import Domain
import Foundation

/// SDK authentication operations used by the existing auth flow while SessionRuntime is migrated.
/// The returned PIN key is encrypted; the PIN itself is never retained by this adapter.
public struct SDKAuthenticationService: Sendable {
    private let sessionClient: SDKSessionClient

    public init(client: Client) {
        sessionClient = SDKSessionClient(client: client)
    }

    public init(sessionClient: SDKSessionClient) { self.sessionClient = sessionClient }

    public func hashPassword(email: String, password: String, kdf: KeyDerivationParameters) async throws -> String {
        let sdkKDF = try SDKKeyDerivationMapper.kdf(for: kdf)
        return try await sessionClient.withClient {
            try await $0.auth().hashPassword(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password, kdfParams: sdkKDF, purpose: .serverAuthorization
            )
        }
    }

    public func derivePINProtectedUserKey(pin: String) async throws -> String {
        try await sessionClient.withClient { try await $0.crypto().derivePinKey(pin: pin).pinProtectedUserKey }
    }
}
