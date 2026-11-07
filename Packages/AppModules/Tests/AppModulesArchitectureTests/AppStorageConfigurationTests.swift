import Foundation
import SecurityStorage
import Testing

@Suite
struct AppStorageConfigurationTests {
    private let info = [
        "VWBundleIdentifierPrefix": "land.temmi.vaultwarden-macos",
        "VWAppGroupIdentifier": "group.land.temmi.vaultwarden-macos",
        "VWSharedKeychainService": "land.temmi.vaultwarden-macos.shared",
        "VWPrivateKeychainService": "land.temmi.vaultwarden-macos.AuthFeature",
        "VWAppIdentifierPrefix": "AB123CDE45.",
    ]

    @Test(arguments: ["", ".ios", ".autofill", ".ios.autofill"])
    func allFourBundlesKeepExistingStorageNames(suffix: String) throws {
        let configuration = try AppStorageConfiguration(
            info: info,
            bundleIdentifier: "land.temmi.vaultwarden-macos" + suffix
        )
        #expect(configuration.appGroupIdentifier == "group.land.temmi.vaultwarden-macos")
        #expect(configuration.sharedKeychainAccessGroup == "AB123CDE45.land.temmi.vaultwarden-macos.shared")
        #expect(configuration.privateKeychainService == "land.temmi.vaultwarden-macos.AuthFeature")
    }

    @Test
    func contributorIdentifiersAreNotCoupledToOriginalBundlePrefix() throws {
        let configuration = try AppStorageConfiguration(info: [
            "VWBundleIdentifierPrefix": "org.example.vault",
            "VWAppGroupIdentifier": "group.org.example.credentials",
            "VWSharedKeychainService": "org.example.shared-credentials",
            "VWPrivateKeychainService": "org.example.private-credentials",
            "VWAppIdentifierPrefix": "ZZ987ZYX65.",
        ], bundleIdentifier: "org.example.vault.ios.autofill")
        #expect(configuration.sharedKeychainAccessGroup == "ZZ987ZYX65.org.example.shared-credentials")
        #expect(configuration.appGroupIdentifier == "group.org.example.credentials")
    }

    @Test
    func keepsTheExactPrefixSeparatorUsedByEntitlements() throws {
        let configuration = try AppStorageConfiguration(
            info: info,
            bundleIdentifier: "land.temmi.vaultwarden-macos"
        )
        #expect(configuration.appIdentifierPrefix == "AB123CDE45.")
        #expect(!configuration.sharedKeychainAccessGroup.contains(".."))
    }

    @Test(arguments: ["VWBundleIdentifierPrefix", "VWAppGroupIdentifier", "VWSharedKeychainService",
                      "VWPrivateKeychainService", "VWAppIdentifierPrefix"])
    func missingSettingsDenyCompositionBeforeContainerOrCredentialFactory(key: String) {
        var configured = info
        configured.removeValue(forKey: key)
        var containerCalls = 0
        var credentialFactoryCalled = false
        #expect(throws: AppStorageConfigurationError.invalidValue(key: key)) {
            let configuration = try AppStorageConfiguration(
                info: configured,
                bundleIdentifier: "land.temmi.vaultwarden-macos"
            )
            _ = try configuration.resolveContainer { _ in
                containerCalls += 1
                return URL(fileURLWithPath: "/synthetic-app-group")
            }
            credentialFactoryCalled = true
        }
        #expect(containerCalls == 0)
        #expect(!credentialFactoryCalled)
    }

    @Test(arguments: [
        ("VWBundleIdentifierPrefix", "org..example"),
        ("VWBundleIdentifierPrefix", "$(VW_BUNDLE_ID_PREFIX)"),
        ("VWAppGroupIdentifier", "org.example.group"),
        ("VWAppGroupIdentifier", "group.org.example "),
        ("VWSharedKeychainService", "org.example/credentials"),
        ("VWSharedKeychainService", "org.example.$(VALUE)"),
        ("VWPrivateKeychainService", "org.-example.private"),
        ("VWPrivateKeychainService", "org.example-.private"),
        ("VWAppIdentifierPrefix", ""),
        ("VWAppIdentifierPrefix", "."),
        ("VWAppIdentifierPrefix", "AB123CDE45"),
        ("VWAppIdentifierPrefix", "$(DEVELOPMENT_TEAM)."),
        ("VWAppIdentifierPrefix", "ab123cde45."),
        ("VWAppIdentifierPrefix", "AB123CDE45.."),
        ("VWAppIdentifierPrefix", "AB123CDE45. "),
        ("VWAppIdentifierPrefix", "AB123CDE4."),
    ])
    func rejectsInvalidAndUnexpandedValues(key: String, value: String) {
        var configured = info
        configured[key] = value
        #expect(throws: AppStorageConfigurationError.invalidValue(key: key)) {
            _ = try AppStorageConfiguration(info: configured, bundleIdentifier: "land.temmi.vaultwarden-macos")
        }
    }

    @Test(arguments: [nil, "", "org.other.app", "land.temmi.vaultwarden-macos-foreign.ios",
                      "land.temmi.vaultwarden-macos.$(VALUE)"] as [String?])
    func rejectsMissingOrForeignBundleIdentity(bundle: String?) {
        #expect(throws: AppStorageConfigurationError.invalidValue(key: "CFBundleIdentifier")) {
            _ = try AppStorageConfiguration(info: info, bundleIdentifier: bundle)
        }
    }

    @Test
    func privateAndSharedKeychainNamespacesCannotCoincide() {
        var configured = info
        configured["VWPrivateKeychainService"] = configured["VWSharedKeychainService"]
        #expect(throws: AppStorageConfigurationError.invalidValue(key: "VWPrivateKeychainService")) {
            _ = try AppStorageConfiguration(info: configured, bundleIdentifier: "land.temmi.vaultwarden-macos")
        }
    }

    @Test
    func resolvesOnlyTheConfiguredGroup() throws {
        let configuration = try AppStorageConfiguration(info: info, bundleIdentifier: "land.temmi.vaultwarden-macos")
        var requestedGroups: [String] = []
        let expected = URL(fileURLWithPath: "/synthetic-app-group")
        let result = try configuration.resolveContainer { group in
            requestedGroups.append(group)
            return expected
        }
        #expect(result == expected)
        #expect(requestedGroups == ["group.land.temmi.vaultwarden-macos"])
    }

    @Test(arguments: [nil, URL(string: "https://example.invalid/container")] as [URL?])
    func missingOrNonFileContainerBlocksCredentialFactory(container: URL?) throws {
        let configuration = try AppStorageConfiguration(info: info, bundleIdentifier: "land.temmi.vaultwarden-macos")
        var credentialFactoryCalled = false
        #expect(throws: AppStorageConfigurationError.sharedContainerUnavailable) {
            _ = try configuration.resolveContainer { _ in container }
            credentialFactoryCalled = true
        }
        #expect(!credentialFactoryCalled)
    }

    @Test
    func diagnosticsIdentifyTheSettingWithoutIncludingItsValue() {
        var configured = info
        let invalidValue = "sensitive-fixture-value/$(TEAM)"
        configured["VWAppIdentifierPrefix"] = invalidValue
        do {
            _ = try AppStorageConfiguration(info: configured, bundleIdentifier: "land.temmi.vaultwarden-macos")
            Issue.record("Invalid configuration was accepted")
        } catch {
            #expect(error.localizedDescription.contains("VWAppIdentifierPrefix"))
            #expect(!error.localizedDescription.contains(invalidValue))
            #expect(!error.localizedDescription.contains("AB123CDE45"))
        }
    }
}
