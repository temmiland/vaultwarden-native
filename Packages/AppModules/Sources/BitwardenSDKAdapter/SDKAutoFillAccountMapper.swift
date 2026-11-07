import AutoFillContract
import BitwardenSdk
import Domain
import Foundation

public enum SDKAutoFillAccountMappingError: Error, Equatable {
    case missingServer
    case invalidKDF
}

/// Shared account metadata is a SDK-free wire value. Validate numeric bounds before converting
/// to SDK integers; malformed/legacy values must never trap or silently select another KDF.
public enum SDKAutoFillAccountMapper {
    public static func environment(for account: SharedAccountInfo) throws -> Domain.ServerEnvironment {
        guard let baseURL = account.serverBaseURL else { throw SDKAutoFillAccountMappingError.missingServer }
        guard ServerURLPolicy.isPermitted(baseURL) else { throw ServerEnvironmentError.invalidBaseURL }
        return try Domain.ServerEnvironment(baseURL: baseURL)
    }

    public static func kdf(for account: SharedAccountInfo) throws -> Kdf {
        do {
            let parameters = try SDKKeyDerivationMapper.parameters(
                type: account.kdfType,
                iterations: account.kdfIterations,
                memory: account.kdfMemory,
                parallelism: account.kdfParallelism
            )
            return try SDKKeyDerivationMapper.kdf(for: parameters)
        } catch {
            throw SDKAutoFillAccountMappingError.invalidKDF
        }
    }
}
