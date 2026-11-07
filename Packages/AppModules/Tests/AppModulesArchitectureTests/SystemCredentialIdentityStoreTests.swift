import AuthenticationServices
import Domain
@testable import PlatformServices
import Testing

@Suite
struct SystemCredentialIdentityStoreTests {
    @Test(arguments: ["enabled", "disabled", "non-incremental"])
    func incrementalStoreCapabilityIsRequiredWithoutReplaceAllFallback(_ capability: String) throws {
        let enabled = capability != "disabled", incremental = capability != "non-incremental"
        if capability == "enabled" {
            try SystemCredentialIdentityStore.requireIncrementalStore(
                isEnabled: enabled,
                supportsIncrementalUpdates: incremental
            )
        } else {
            let error: SystemCredentialIdentityStoreError = enabled ? .incrementalUpdatesUnavailable : .disabled
            #expect(throws: error) {
                try SystemCredentialIdentityStore.requireIncrementalStore(
                    isEnabled: enabled,
                    supportsIncrementalUpdates: incremental
                )
            }
        }
    }

    @Test
    func incrementalMappingKeepsDecodedBytesAndAcceptsAnEmptyUserHandle() throws {
        let identity = PasskeyProjectionCacheFixture.identity()
        let mapped = try SystemCredentialIdentityStore.makeIncrementalPasskeyIdentities(from: identity)
        let passkey = try #require(mapped.first as? ASPasskeyCredentialIdentity)
        #expect(mapped.count == 1 && passkey.credentialID == identity.credentialID)
        #expect(passkey.userHandle == Data() && passkey.recordIdentifier == "saved")
    }

    @Test(arguments: ["kind", "id", "rp", "cipher", "credential", "handle", "user"])
    func incrementalMappingThrowsInsteadOfSilentlyOmittingAnInvalidIdentity(_ field: String) {
        let identity = CredentialIdentityDescriptor(
            id: field == "id" ? "" : "passkey",
            kind: field == "kind" ? .password : .passkey,
            serviceIdentifier: field == "rp" ? "" : "example.com",
            user: field == "user" ? "" : "alice",
            label: nil,
            credentialID: field == "credential" ? Data() : Data([1]),
            userHandle: field == "handle" ? nil : Data(),
            recordIdentifier: CipherID(rawValue: field == "cipher" ? "" : "saved")
        )
        #expect(throws: SystemCredentialIdentityStoreError.invalidPasskeyIdentity) {
            try SystemCredentialIdentityStore.makeIncrementalPasskeyIdentities(from: identity)
        }
    }

    @Test
    func platformAdapterMapsPasswordAndPasskeyDescriptorsWithoutCallingTheOSStore() {
        let password = CredentialIdentityDescriptor(
            id: "password", kind: .password, serviceIdentifier: "https://example.com", user: "alice",
            label: nil, credentialID: nil, userHandle: nil, recordIdentifier: CipherID(rawValue: "cipher-password")
        )
        let passkey = CredentialIdentityDescriptor(
            id: "passkey", kind: .passkey, serviceIdentifier: "example.com", user: "alice",
            label: "Example", credentialID: Data([1, 2]), userHandle: Data([3]),
            recordIdentifier: CipherID(rawValue: "cipher-passkey")
        )

        let identities = SystemCredentialIdentityStore.makeSystemIdentities(from: [password, passkey])

        let passwordIdentity = identities.compactMap { $0 as? ASPasswordCredentialIdentity }.first
        let passkeyIdentity = identities.compactMap { $0 as? ASPasskeyCredentialIdentity }.first
        #expect(passwordIdentity?.recordIdentifier == "cipher-password")
        #expect(passkeyIdentity?.recordIdentifier == "cipher-passkey")
        #expect(passkeyIdentity?.credentialID == Data([1, 2]))
    }

    @Test
    func platformAdapterRejectsDescriptorsMissingRequiredSystemFields() {
        let passwordWithoutUser = CredentialIdentityDescriptor(
            id: "password", kind: .password, serviceIdentifier: "https://example.com", user: nil,
            label: nil, credentialID: nil, userHandle: nil, recordIdentifier: CipherID(rawValue: "cipher")
        )
        let passkeyWithoutHandle = CredentialIdentityDescriptor(
            id: "passkey", kind: .passkey, serviceIdentifier: "example.com", user: "alice",
            label: nil, credentialID: Data([1]), userHandle: nil, recordIdentifier: CipherID(rawValue: "cipher")
        )

        #expect(
            SystemCredentialIdentityStore.makeSystemIdentities(from: [passwordWithoutUser, passkeyWithoutHandle]).isEmpty
        )
    }
}
