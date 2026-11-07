import AutoFillContract
import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Testing

@Suite
struct SDKAutoFillAccountMapperTests {
    @Test
    func supportedKDFsRetainTheExistingValuesAndDefaults() throws {
        #expect(try SDKAutoFillAccountMapper.kdf(for: account()) == .pbkdf2(iterations: 600_000))
        #expect(try SDKAutoFillAccountMapper.kdf(for: account(type: 1, iterations: 3)) ==
            .argon2id(iterations: 3, memory: 64, parallelism: 4))
        #expect(try SDKAutoFillAccountMapper.kdf(for: account(type: 1, iterations: 3, memory: 32, parallelism: 2)) ==
            .argon2id(iterations: 3, memory: 32, parallelism: 2))
        #expect(try SDKAutoFillAccountMapper.kdf(for: account(iterations: 2_000_000)) ==
            .pbkdf2(iterations: 2_000_000))
    }

    @Test(arguments: [-1, 0, 2_000_001, Int(UInt32.max), Int(UInt32.max) + 1])
    func invalidIterationCountsThrowInsteadOfTrappingOrDefaulting(_ iterations: Int) {
        #expect(throws: SDKAutoFillAccountMappingError.invalidKDF) {
            _ = try SDKAutoFillAccountMapper.kdf(for: account(iterations: iterations))
        }
    }

    @Test(arguments: [-1, 0, Int(UInt32.max) + 1])
    func invalidArgonMemoryOrParallelismThrowsBeforeSDKConversion(_ value: Int) {
        for info in [
            account(type: 1, memory: value),
            account(type: 1, parallelism: value),
        ] {
            #expect(throws: SDKAutoFillAccountMappingError.invalidKDF) {
                _ = try SDKAutoFillAccountMapper.kdf(for: info)
            }
        }
    }

    @Test(arguments: [-1, 2, 256])
    func unknownKDFTypesCannotSilentlyBecomePBKDF2(_ type: Int) {
        #expect(throws: SDKAutoFillAccountMappingError.invalidKDF) {
            _ = try SDKAutoFillAccountMapper.kdf(for: account(type: type))
        }
    }

    @Test
    func environmentPreservesReverseProxyRoutesAndNeverInventsALegacyServer() throws {
        let info = account(server: URL(string: "https://vault.example.com/base/"))
        let environment = try SDKAutoFillAccountMapper.environment(for: info)
        #expect(environment.baseURL.absoluteString == "https://vault.example.com/base")
        #expect(environment.apiURL.absoluteString == "https://vault.example.com/base/api")
        #expect(environment.identityURL.absoluteString == "https://vault.example.com/base/identity")
        #expect(throws: SDKAutoFillAccountMappingError.missingServer) {
            _ = try SDKAutoFillAccountMapper.environment(for: account(server: nil))
        }
        #expect(throws: ServerEnvironmentError.invalidBaseURL) {
            _ = try SDKAutoFillAccountMapper.environment(for: account(server: URL(string: "file:///invalid")))
        }
    }

    @Test
    func SDKFreeMetadataKeepsItsJSONFieldsButRedactsDescriptions() throws {
        let info = account()
        let data = try JSONEncoder().encode(info)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["userId"] as? String == info.userId)
        #expect(json["kdfType"] as? Int == info.kdfType)
        #expect(json["encryptedPrivateKey"] as? String == info.encryptedPrivateKey)
        #expect(try JSONDecoder().decode(SharedAccountInfo.self, from: data).serverBaseURL == info.serverBaseURL)
        for description in [String(describing: info), String(reflecting: info)] {
            #expect(!description.contains(info.email))
            #expect(!description.contains(info.encryptedPrivateKey))
        }
    }

    @Test(arguments: ["http://vault.example.com", "https://user:password@vault.example.com",
                      "https://vault.example.com?token=fixture", "https://vault.example.com#fragment"])
    func extensionBootstrapCannotUseAnUnsafeCredentialServer(_ value: String) {
        #expect(throws: ServerEnvironmentError.invalidBaseURL) {
            _ = try SDKAutoFillAccountMapper.environment(for: account(server: URL(string: value)))
        }
    }

    private func account(
        type: Int = 0,
        iterations: Int = 600_000,
        memory: Int? = nil,
        parallelism: Int? = nil,
        server: URL? = URL(string: "https://vault.example.com")
    ) -> SharedAccountInfo {
        SharedAccountInfo(
            userId: "account-1",
            email: "test@example.com",
            kdfType: type,
            kdfIterations: iterations,
            kdfMemory: memory,
            kdfParallelism: parallelism,
            encryptedPrivateKey: "fake-wrapped-key",
            serverBaseURL: server
        )
    }
}
