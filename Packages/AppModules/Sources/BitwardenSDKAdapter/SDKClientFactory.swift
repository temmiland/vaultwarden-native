import BitwardenSdk
import Foundation

/// Shared client configuration for the app and credential-provider extension. Legacy callers
/// provide URLs and bundle metadata here; the future SessionRuntime owns the resulting client.
public enum SDKClientFactory {
    public static var deviceType: DeviceType {
        #if os(iOS)
            .iOs
        #else
            .macOsDesktop
        #endif
    }

    public static func userAgent(applicationVersion: String) -> String {
        #if os(iOS)
            "Vaultwarden-iOS/\(applicationVersion)"
        #else
            "Vaultwarden-macOS/\(applicationVersion)"
        #endif
    }

    public static func makeSettings(
        identityURL: URL,
        apiURL: URL,
        deviceIdentifier: String,
        applicationVersion: String
    ) -> ClientSettings {
        ClientSettings(
            identityUrl: identityURL.absoluteString,
            apiUrl: apiURL.absoluteString,
            userAgent: userAgent(applicationVersion: applicationVersion),
            deviceType: deviceType,
            deviceIdentifier: deviceIdentifier,
            bitwardenClientVersion: nil,
            bitwardenPackageType: nil
        )
    }

    public static func makeClient(tokenProvider: ClientManagedTokens, settings: ClientSettings) -> Client {
        // This client has no UEM provider. Keep its empty profile scoped to this SDK session.
        Client(tokenProvider: tokenProvider, settings: settings, managedSettings: ManagedSettingsBindingClient())
    }
}
