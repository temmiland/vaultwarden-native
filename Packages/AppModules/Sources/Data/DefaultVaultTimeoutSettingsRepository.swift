import Domain
import Foundation

/// UserDefaults-backed storage for the non-secret idle-timeout preference. The key is intentionally
/// retained from the former SettingsFeature store so upgrades keep the user's current selection.
public final class DefaultVaultTimeoutSettingsRepository: VaultTimeoutSettingsRepository, @unchecked Sendable {
    private static let defaultsKey = "land.temmi.vaultwarden-macos.SettingsFeature.vaultTimeoutPreference"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() throws -> VaultTimeoutPreference {
        guard let data = userDefaults.data(forKey: Self.defaultsKey) else { return .default }
        return try JSONDecoder().decode(VaultTimeoutPreference.self, from: data)
    }

    public func save(_ preference: VaultTimeoutPreference) throws {
        userDefaults.set(try JSONEncoder().encode(preference), forKey: Self.defaultsKey)
    }
}
