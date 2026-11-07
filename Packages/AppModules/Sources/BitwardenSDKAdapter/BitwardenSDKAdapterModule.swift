import Domain

/// The only new target permitted to depend on the generated Bitwarden SDK. SDK imports are added
/// here as operations are migrated, never in presentation targets.
public enum BitwardenSDKAdapterModule {
    public static let name = "BitwardenSDKAdapter"
}
