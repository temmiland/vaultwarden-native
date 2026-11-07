/// Existing shared Keychain account names. These are wire compatibility, not live dependencies
/// or secrets. App-group/container/keychain entitlement configuration stays at composition.
public enum AutoFillStorageKeys {
    public static let sharedUserKeyAccount = "auth.sharedAutofillUnlock.v2"
    public static let legacySharedUserKeyAccount = "auth.sharedAutofillUserKey"
    public static let sharedUnlockEpochAccount = "auth.sharedAutofillRevocationEpoch"
    public static let sharedAccountInfoAccount = "auth.sharedAccountInfo"
    public static let sharedTokensAccount = "auth.sharedTokens.v2"
    public static let legacySharedTokensAccount = "auth.sharedTokens"
}
