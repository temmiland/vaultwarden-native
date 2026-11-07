import Foundation
import SecurityStorage
import Testing

/// Port of the existing Core smoke: synthetic UUID key in the same test-only service, never
/// signed-in data. This checks this Mac's Keychain API, not signed App Group/device entitlements.
@Suite
struct KeychainPlatformSmokeTests {
    @Test
    func realKeychainAddUpdateReadAndDeleteRoundTrip() throws {
        let keychain = DefaultKeychainStore(service: "land.temmi.vaultwarden-macos.tests")
        let key = "test-\(UUID().uuidString)"
        defer { try? keychain.remove(key) }
        #expect(throws: KeychainStoreError.notFound) { _ = try keychain.read(key) }
        try keychain.write(Data("fixture-secret".utf8), for: key)
        #expect(try keychain.read(key) == Data("fixture-secret".utf8))
        try keychain.write(Data("fixture-updated".utf8), for: key)
        #expect(try keychain.read(key) == Data("fixture-updated".utf8))
        try keychain.remove(key)
        #expect(throws: KeychainStoreError.notFound) { _ = try keychain.read(key) }
    }
}
