import BitwardenSdk
import Domain

/// One conversion for app prelogin, returning unlock and extension bootstrap. Only omitted
/// values use the existing defaults; invalid/unknown values never trap or select another KDF.
public enum SDKKeyDerivationMapper {
    public static func parameters(type: Int?, iterations: Int?, memory: Int?, parallelism: Int?) throws -> KeyDerivationParameters {
        func positive(_ value: Int) throws -> UInt32 {
            guard let result = UInt32(exactly: value), result > 0 else { throw AuthFlowError.invalidEncryptionParameters }
            return result
        }
        let parameters: KeyDerivationParameters
        switch type ?? 0 {
        case 0:
            parameters = .pbkdf2(iterations: try positive(iterations ?? 600_000))
        case 1:
            parameters = .argon2id(
                iterations: try positive(iterations ?? 3),
                memory: try positive(memory ?? 64),
                parallelism: try positive(parallelism ?? 4)
            )
        default:
            throw AuthFlowError.invalidEncryptionParameters
        }
        try validateCost(parameters)
        return parameters
    }

    public static func kdf(for parameters: KeyDerivationParameters) throws -> Kdf {
        try validateCost(parameters)
        switch parameters {
        case let .pbkdf2(iterations):
            guard iterations > 0 else { throw AuthFlowError.invalidEncryptionParameters }
            return .pbkdf2(iterations: iterations)
        case let .argon2id(iterations, memory, parallelism):
            guard iterations > 0, memory > 0, parallelism > 0 else { throw AuthFlowError.invalidEncryptionParameters }
            return .argon2id(iterations: iterations, memory: memory, parallelism: parallelism)
        }
    }

    /// Local resource policy, NOT a claim about the server's supported KDF range. Untrusted
    /// prelogin/cache metadata must not request UInt32.max iterations or multi-gigabyte memory.
    /// Reject, never clamp: a different KDF would derive the wrong key. Older low-cost accounts
    /// remain readable; this does not silently upgrade their cryptography.
    private static func validateCost(_ parameters: KeyDerivationParameters) throws {
        switch parameters {
        case let .pbkdf2(iterations):
            guard (1 ... 2_000_000).contains(iterations) else { throw AuthFlowError.invalidEncryptionParameters }
        case let .argon2id(iterations, memory, parallelism):
            guard (1 ... 10).contains(iterations), (1 ... 256).contains(memory),
                  (1 ... 16).contains(parallelism), memory >= parallelism,
                  UInt64(iterations) * UInt64(memory) <= 768 else { throw AuthFlowError.invalidEncryptionParameters }
        }
    }
}
