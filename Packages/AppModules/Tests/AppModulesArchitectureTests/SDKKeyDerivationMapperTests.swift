import BitwardenSDKAdapter
import Domain
import Testing

@Suite
struct SDKKeyDerivationMapperTests {
    @Test
    func omittedValuesKeepExistingAlgorithmSpecificDefaults() throws {
        #expect(try parameters() == .pbkdf2(iterations: 600_000))
        #expect(try parameters(type: 1) == .argon2id(iterations: 3, memory: 64, parallelism: 4))
        #expect(try SDKKeyDerivationMapper.kdf(for: parameters(type: 1, iterations: 5, memory: 32, parallelism: 2)) ==
            .argon2id(iterations: 5, memory: 32, parallelism: 2))
        #expect(try parameters(iterations: 2_000_000) == .pbkdf2(iterations: 2_000_000))
    }

    @Test(arguments: [-1, 0, 2_000_001, Int(UInt32.max), Int(UInt32.max) + 1, Int.max, Int.min])
    func invalidNumericValuesThrowBeforeSDKConversion(_ value: Int) {
        for type in [0, 1] {
            #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try parameters(
                type: type,
                iterations: value
            ) }
        }
        #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try parameters(type: 1, memory: value) }
        #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try parameters(type: 1, parallelism: value) }
    }

    @Test(arguments: [-1, 2, 256, Int.max])
    func unknownAlgorithmsNeverFallBackToPBKDF2(_ value: Int) {
        #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try parameters(type: value) }
    }

    @Test(arguments: [KeyDerivationParameters.argon2id(iterations: 11, memory: 64, parallelism: 4),
                      .argon2id(iterations: 3, memory: 257, parallelism: 4),
                      .argon2id(iterations: 3, memory: 64, parallelism: 17),
                      .argon2id(iterations: 4, memory: 256, parallelism: 4),
                      .argon2id(iterations: 1, memory: 1, parallelism: 4),
                      .pbkdf2(iterations: .max)])
    func directSDKInputsCannotBypassTheResourceBudget(_ value: KeyDerivationParameters) {
        #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try SDKKeyDerivationMapper.kdf(for: value) }
    }

    @Test
    func excessivePreloginCostsAreRejectedRatherThanClamped() {
        for values in [(11, 64, 4), (3, 257, 4), (3, 64, 17), (4, 256, 4), (1, 1, 4)] {
            #expect(throws: AuthFlowError.invalidEncryptionParameters) {
                _ = try parameters(type: 1, iterations: values.0, memory: values.1, parallelism: values.2)
            }
        }
    }

    @Test(arguments: [KeyDerivationParameters.pbkdf2(iterations: 0),
                      .argon2id(iterations: 0, memory: 64, parallelism: 4),
                      .argon2id(iterations: 3, memory: 0, parallelism: 4),
                      .argon2id(iterations: 3, memory: 64, parallelism: 0)])
    func explicitlyConstructedInvalidDomainValuesCannotBypassTheAdapter(_ value: KeyDerivationParameters) {
        #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try SDKKeyDerivationMapper.kdf(for: value) }
    }

    private func parameters(
        type: Int? = nil,
        iterations: Int? = nil,
        memory: Int? = nil,
        parallelism: Int? = nil
    ) throws -> KeyDerivationParameters {
        try SDKKeyDerivationMapper.parameters(
            type: type,
            iterations: iterations,
            memory: memory,
            parallelism: parallelism
        )
    }
}
