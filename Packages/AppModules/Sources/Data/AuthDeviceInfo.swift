/// Identifies this installation to the Vaultwarden/Bitwarden identity server. The identifier is a
/// random UUID generated once and persisted in the Keychain (via `AuthCredentialStore`) so it stays
/// stable across logins and app relaunches.
public struct DeviceInfo: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Stable per-install identifier, sent as `deviceIdentifier`.
    public let identifier: String

    /// Human readable device name, sent as `deviceName`.
    public let name: String

    /// Bitwarden's numeric device type code sent to the server (`0`=Android, `1`=iOS, ...,
    /// `7`=macOS desktop - independent of the vendored SDK's own internal `DeviceType` FFI
    /// wire encoding, which is 1-indexed for a different reason and not used here).
    public let typeCode: Int = {
        #if os(iOS)
            1
        #else
            7
        #endif
    }()

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }

    public var description: String { "DeviceInfo(<redacted>)" }
    public var debugDescription: String { description }
}
