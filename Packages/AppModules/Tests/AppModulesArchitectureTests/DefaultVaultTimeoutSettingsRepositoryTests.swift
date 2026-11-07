import Data
import Domain
import Foundation
import Testing

@Suite
struct DefaultVaultTimeoutSettingsRepositoryTests {
    @Test
    func missingPreferenceUsesDefault() throws {
        let (defaults, repository, suite) = makeRepository()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(try repository.load() == .default)
    }

    @Test
    func saveThenLoadPreservesThePreferenceAndLegacyKey() throws {
        let (defaults, repository, suite) = makeRepository()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = VaultTimeoutPreference(duration: .fiveMinutes, action: .logOut)

        try repository.save(preference)

        #expect(try repository.load() == preference)
        #expect(defaults.data(forKey: "land.temmi.vaultwarden-macos.SettingsFeature.vaultTimeoutPreference") != nil)
    }

    @Test
    func malformedStoredPreferenceIsReportedRatherThanSilentlyReset() throws {
        let (defaults, repository, suite) = makeRepository()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Foundation.Data("not-a-preference".utf8),
            forKey: "land.temmi.vaultwarden-macos.SettingsFeature.vaultTimeoutPreference"
        )

        #expect(throws: DecodingError.self) { try repository.load() }
    }

    private func makeRepository() -> (UserDefaults, DefaultVaultTimeoutSettingsRepository, String) {
        let suite = "DefaultVaultTimeoutSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, DefaultVaultTimeoutSettingsRepository(userDefaults: defaults), suite)
    }
}
