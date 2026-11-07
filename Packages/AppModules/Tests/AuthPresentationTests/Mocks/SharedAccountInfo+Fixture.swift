import AutoFillContract
import Foundation

extension SharedAccountInfo {
    static func fixture(userID: String = "user-1") -> Self {
        Self(
            userId: userID,
            email: "test@example.com",
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedPrivateKey: "fake-test-wrapped-private-key",
            serverBaseURL: URL(string: "https://vault.example.com")!
        )
    }
}
