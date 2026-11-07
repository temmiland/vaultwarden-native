@testable import AppFeature
@testable import AuthPresentation
@testable import AutoFillContract
@testable import AutoFillData
@testable import AutoFillFeature
@testable import BitwardenSDKAdapter
@testable import Data
@testable import Domain
import Foundation
@testable import Networking
@testable import PlatformServices
@testable import SecurityStorage
@testable import SendPresentation
@testable import SettingsPresentation
@testable import SharedUI
import Testing
@testable import VaultPresentation

@Test
func targetGraphCompilesWithoutLegacyFeatureDependencies() {
    #expect(AccountID(rawValue: "account").rawValue == "account")
    #expect(AutoFillFeatureModule.name == "AutoFillFeature")
}

@Test
func serverEnvironmentNormalizesAReverseProxyBaseURL() throws {
    let environment = try ServerEnvironment(baseURL: #require(URL(string: "https://vault.example.com/vault/")))

    #expect(environment.baseURL.absoluteString == "https://vault.example.com/vault")
    #expect(environment.apiURL.absoluteString == "https://vault.example.com/vault/api")
    #expect(environment.identityURL.absoluteString == "https://vault.example.com/vault/identity")
}

@Test
func autofillContractRejectsFutureSchemasAndDoesNotEncodePlaintextFields() throws {
    let record = EncryptedLoginRecord(id: "cipher-1", deletedAt: nil, encryptedCipherPayload: Data("ciphertext".utf8))
    let envelope = try AutoFillCacheEnvelope(
        accountID: "account-1", revision: 4, generatedAt: .distantPast,
        encryptedLoginRecords: [record], encryptedOrganizationKeys: [:]
    )
    let json = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)

    #expect(!json.contains("password"))
    #expect(!json.contains("totp"))
    #expect(!json.contains("privateKey"))
    #expect(throws: AutoFillCacheContractError.unsupportedSchema(2)) {
        _ = try AutoFillCacheEnvelope(
            schemaVersion: 2, accountID: "account-1", revision: 4, generatedAt: .distantPast,
            encryptedLoginRecords: [], encryptedOrganizationKeys: [:]
        )
    }
}
