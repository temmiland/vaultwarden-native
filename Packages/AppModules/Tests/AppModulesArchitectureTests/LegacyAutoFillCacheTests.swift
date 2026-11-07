import AutoFillContract
import AutoFillData
import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

/// Pure filtering and ownership regression tests for the encrypted extension cache.
@Suite
struct LegacyAutoFillCacheTests {
    @Test
    func legacyAndWrongAccountCachesCannotAuthorizeAnExtensionInvocation() throws {
        let owner = AutoFillAccountIdentity(userID: "user-1", serverBaseURL: URL(string: "https://vault.example.com")!)
        var cache = SharedVaultCacheData(ciphers: [], organizationKeys: [:], updatedAt: .distantPast)
        #expect(throws: SharedVaultCacheError.self) { try cache.validate(for: owner) }
        cache.owner = owner
        cache.revision = UUID()
        try cache.validate(for: owner)
        for other in [
            AutoFillAccountIdentity(userID: "user-2", serverBaseURL: owner.serverBaseURL),
            AutoFillAccountIdentity(userID: owner.userID, serverBaseURL: URL(string: "https://different.example.com")!),
        ] {
            #expect(throws: SharedVaultCacheError.self) { try cache.validate(for: other) }
        }
        let decoded = try JSONDecoder().decode(SharedVaultCacheData.self, from: JSONEncoder().encode(cache))
        #expect(decoded.owner == owner)
        #expect(decoded.revision == cache.revision)
    }

    @Test
    func mutationKeepsTheAccountButAdvancesTheCryptoCacheRevision() {
        let owner = AutoFillAccountIdentity(userID: "user-1", serverBaseURL: URL(string: "https://vault.example.com")!)
        let cache = SharedVaultCacheData(
            ciphers: [],
            organizationKeys: ["org": "fake-wrapped-key"],
            updatedAt: .distantPast,
            owner: owner,
            revision: UUID()
        )
        var response = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        response.id = "cipher-1"
        response.login = CipherLoginDTO(username: "encrypted-user", password: "encrypted-password")
        let updated = LegacyAutoFillCacheStore.upserting(response, into: cache)
        #expect(updated.owner == owner)
        #expect(updated.revision != cache.revision)
        #expect(updated.organizationKeys == cache.organizationKeys)
    }

    @Test
    func onlyLoginTypeCiphersWithLoginDataAreIncluded() {
        var login = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        login.id = "cipher-1"
        login.login = CipherLoginDTO(username: "user", password: "pass")

        var loginWithoutData = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        loginWithoutData.login = nil

        var card = CipherResponseDTO(type: Int(CipherType.card.rawValue))
        card.login = nil

        let result = LegacyAutoFillCacheStore.loginCiphers(from: [login, loginWithoutData, card])

        #expect(result.count == 1)
        #expect(result[0].login?.username == "user")
    }

    @Test
    func cacheDataRoundTripsThroughJSON() throws {
        var login = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        login.id = "cipher-1"
        login.login = CipherLoginDTO(username: "enc-user", password: "enc-pass")
        let original = SharedVaultCacheData(
            ciphers: [login], organizationKeys: ["org-1": "enc-org-key"], updatedAt: Date()
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SharedVaultCacheData.self, from: encoded)

        #expect(decoded.ciphers.first?.id == "cipher-1")
        #expect(decoded.organizationKeys == ["org-1": "enc-org-key"])
    }

    @Test
    func upsertingServerResponseReplacesOnlyThatCipherAndKeepsOrganizationKeys() {
        var original = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        original.id = "cipher-1"
        original.login = CipherLoginDTO(username: "old-user", password: "old-password")
        var unaffected = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        unaffected.id = "cipher-2"
        unaffected.login = CipherLoginDTO(username: "other-user", password: "other-password")
        let cache = SharedVaultCacheData(
            ciphers: [original, unaffected], organizationKeys: ["org-1": "encrypted-key"], updatedAt: .distantPast
        )
        var response = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        response.id = "cipher-1"
        response.login = CipherLoginDTO(username: "new-user", password: "new-password")

        let updated = LegacyAutoFillCacheStore.upserting(response, into: cache)

        #expect(updated.ciphers.count == 2)
        #expect(updated.ciphers.first(where: { $0.id == "cipher-1" })?.login?.username == "new-user")
        #expect(updated.ciphers.first(where: { $0.id == "cipher-2" })?.login?.username == "other-user")
        #expect(updated.organizationKeys == ["org-1": "encrypted-key"])
    }

    @Test
    func upsertingAnArchivedLoginRemovesItFromTheAutofillCache() {
        var original = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        original.id = "cipher-1"
        original.login = CipherLoginDTO(username: "user", password: "password")
        let cache = SharedVaultCacheData(ciphers: [original], organizationKeys: [:], updatedAt: .distantPast)
        var archived = original
        archived.archivedDate = "2026-09-26T00:00:00.000Z"

        let updated = LegacyAutoFillCacheStore.upserting(archived, into: cache)

        #expect(updated.ciphers.isEmpty)
    }

    @Test(arguments: [1, 2, -1])
    func repromptOrUnknownProtectionRemovesExistingCachedLogin(_ flag: Int) {
        var original = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        original.id = "cipher-1"
        original.login = CipherLoginDTO(username: "encrypted-user", password: "encrypted-password")
        let cache = SharedVaultCacheData(ciphers: [original], organizationKeys: [:], updatedAt: .distantPast)
        var protected = original
        protected.reprompt = flag

        #expect(LegacyAutoFillCacheStore.loginCiphers(from: [protected]).isEmpty)
        #expect(LegacyAutoFillCacheStore.upserting(protected, into: cache).ciphers.isEmpty)
        #expect(protected.reprompt == flag)
    }

    @Test
    func hiddenPasswordPermissionsAndMissingIDsAreNotAutoFillCandidates() {
        var login = CipherResponseDTO(type: Int(CipherType.login.rawValue))
        login.login = CipherLoginDTO(username: "encrypted-user", password: "encrypted-password")
        #expect(LegacyAutoFillCacheStore.loginCiphers(from: [login]).isEmpty)
        login.id = ""
        #expect(LegacyAutoFillCacheStore.loginCiphers(from: [login]).isEmpty)
        login.id = "cipher-1"
        login.viewPassword = false
        #expect(LegacyAutoFillCacheStore.loginCiphers(from: [login]).isEmpty)
    }
}

private extension CipherResponseDTO {
    init(type: Int) {
        self.init(
            id: nil, organizationId: nil, folderId: nil, collectionIds: nil, type: type, name: nil,
            notes: nil, favorite: nil, reprompt: nil, key: nil, login: nil, card: nil, identity: nil,
            secureNote: nil, sshKey: nil, organizationUseTotp: nil, edit: nil, viewPassword: nil,
            attachments: nil, revisionDate: nil, creationDate: nil, deletedDate: nil, archivedDate: nil
        )
    }
}

private extension CipherLoginDTO {
    init(username: String, password: String) {
        self.init(
            username: username, password: password, passwordRevisionDate: nil, uris: nil, totp: nil,
            autofillOnPageLoad: nil, fido2Credentials: nil
        )
    }
}
