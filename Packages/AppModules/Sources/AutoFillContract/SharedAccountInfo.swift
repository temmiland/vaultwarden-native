import Foundation

/// SDK-free metadata inside the existing shared unlock envelope. Crypto/KDF mapping belongs
/// to the SDK adapter; key material and grant persistence belong to Data, not this contract.
public struct SharedAccountInfo: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let userId: String
    public let email: String
    public let kdfType: Int
    public let kdfIterations: Int
    public let kdfMemory: Int?
    public let kdfParallelism: Int?
    public let encryptedPrivateKey: String
    /// The server this account belongs to, so the extension can build `ClientSettings` from the
    /// real environment instead of a placeholder. Optional because records written before this
    /// field existed remain decodable for recovery, but cannot authorize an extension invocation.
    public let serverBaseURL: URL?

    public init(
        userId: String,
        email: String,
        kdfType: Int,
        kdfIterations: Int,
        kdfMemory: Int?,
        kdfParallelism: Int?,
        encryptedPrivateKey: String,
        serverBaseURL: URL? = nil
    ) {
        self.userId = userId
        self.email = email
        self.kdfType = kdfType
        self.kdfIterations = kdfIterations
        self.kdfMemory = kdfMemory
        self.kdfParallelism = kdfParallelism
        self.encryptedPrivateKey = encryptedPrivateKey
        self.serverBaseURL = serverBaseURL
    }

    public var description: String { "SharedAccountInfo(<redacted>)" }
    public var debugDescription: String { description }
}
