import Testing
@testable import BitwardenSdk

/// Proves the locally-built macOS xcframework actually links and the Rust crypto core responds —
/// the single biggest technical risk for this project (see .claude/plans design doc). No server
/// needed: just constructing a `Client` and calling a pure-local SDK function (password strength,
/// no network) is enough to prove the FFI boundary works end to end on macOS.
private final class NoOpTokenProvider: ClientManagedTokens {
    func getAccessToken() async -> String? { nil }
}

@Suite
struct ClientSmokeTests {
    @Test
    func clientInitializesAndRespondsOnMacOS() async throws {
        let settings = ClientSettings(
            identityUrl: "https://vault.example.com/identity",
            apiUrl: "https://vault.example.com/api",
            userAgent: "vaultwarden-macos-smoke-test",
            deviceType: .macOsDesktop,
            deviceIdentifier: "smoke-test-device",
            bitwardenClientVersion: "0.0.1",
            bitwardenPackageType: nil
        )

        let client = Client(tokenProvider: NoOpTokenProvider(), settings: settings)

        // A pure-local, no-network SDK call (password strength estimation) — enough to prove the
        // Rust core is genuinely running behind the FFI, not just that the class initialized.
        let strength = client.auth().passwordStrength(
            password: "correct horse battery staple",
            email: "test@example.com",
            additionalInputs: []
        )

        // zxcvbn score is 0-4; a long multi-word passphrase should score well above the minimum.
        #expect(strength >= 3)
    }
}
