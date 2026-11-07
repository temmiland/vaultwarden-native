import BitwardenSdk
import Foundation

/// Adapter-internal SDK seam. Domain/Presentation never receive these SDK values; tests can
/// substitute crypto without initializing a real FFI-backed unlocked session.
public protocol SendCryptoServicing: Sendable {
    func decryptList(_ sends: [Send]) throws -> [SendListView]
    func decrypt(_ send: Send) throws -> SendView
    func encrypt(_ sendView: SendView) throws -> Send
    func encryptFile(send: Send, plaintextURL: URL, encryptedURL: URL) throws
}

/// Live implementation backed by the real vendored crypto core. Constructed with the `Client`
/// owned by the session runtime — this package never rolls its own crypto.
public struct SDKSendCryptoService: SendCryptoServicing, Sendable {
    private let sessionClient: SDKSessionClient

    public init(client: Client) {
        sessionClient = SDKSessionClient(client: client)
    }

    public init(sessionClient: SDKSessionClient) { self.sessionClient = sessionClient }

    public func decryptList(_ sends: [Send]) throws -> [SendListView] {
        try sessionClient.withClient { try $0.sends().decryptList(sends: sends) }
    }

    public func decrypt(_ send: Send) throws -> SendView {
        try sessionClient.withClient { try $0.sends().decrypt(send: send) }
    }

    public func encrypt(_ sendView: SendView) throws -> Send {
        try sessionClient.withClient { try $0.sends().encrypt(send: sendView) }
    }

    public func encryptFile(send: Send, plaintextURL: URL, encryptedURL: URL) throws {
        try sessionClient.withClient {
            try $0.sends().encryptFile(
                send: send, decryptedFilePath: plaintextURL.path, encryptedFilePath: encryptedURL.path
            )
        }
    }
}
