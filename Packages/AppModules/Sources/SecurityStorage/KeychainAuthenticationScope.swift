import Foundation

/// Opaque platform authentication handle. Domain and presentation never see Apple contexts.
public struct KeychainAuthenticationContext: @unchecked Sendable {
    public let value: AnyObject
    public init(_ value: AnyObject) { self.value = value }
}

/// Exists only while one authenticated operation runs. The platform adapter invalidates the
/// underlying context afterwards; this is not a global authentication reuse window.
public enum KeychainAuthenticationScope {
    @TaskLocal public static var current: KeychainAuthenticationContext?
}
