import AutoFillContract
import BitwardenSDKAdapter
import Domain
import Foundation

extension StoredAuthAccount {
    public var keyDerivationParameters: KeyDerivationParameters {
        get throws {
            try SDKKeyDerivationMapper.parameters(
                type: kdfType,
                iterations: kdfIterations,
                memory: kdfMemory,
                parallelism: kdfParallelism
            )
        }
    }

    /// Use the same validated parameters for main-app unlock and extension publication, including
    /// legacy Argon2 records that omitted iterations. Do not apply PBKDF2 defaults to Argon2.
    public func autoFillAccountInfo() throws -> SharedAccountInfo {
        let type: Int
        let iterations: Int
        let memory: Int?
        let parallelism: Int?
        switch try keyDerivationParameters {
        case let .pbkdf2(count):
            type = 0; iterations = Int(count); memory = nil; parallelism = nil
        case let .argon2id(count, memoryCount, parallelismCount):
            type = 1; iterations = Int(count); memory = Int(memoryCount); parallelism = Int(parallelismCount)
        }
        return SharedAccountInfo(
            userId: userId,
            email: email,
            kdfType: type,
            kdfIterations: iterations,
            kdfMemory: memory,
            kdfParallelism: parallelism,
            encryptedPrivateKey: encryptedPrivateKey,
            serverBaseURL: serverBaseURL
        )
    }
}

extension TokenSuccessResponse {
    /// Persist the exact parameters used to hash/unlock, not accidental PBKDF2 defaults when
    /// token metadata omits fields. Explicit metadata must agree with the prelogin parameters.
    public func makeStoredAccount(
        userID: String,
        email: String,
        serverBaseURL: URL,
        parameters: KeyDerivationParameters
    ) throws -> StoredAuthAccount {
        let type: Int
        let iterations: Int
        let memory: Int?
        let parallelism: Int?
        switch parameters {
        case let .pbkdf2(count):
            type = 0; iterations = Int(count); memory = nil; parallelism = nil
        case let .argon2id(count, memoryCount, parallelismCount):
            type = 1; iterations = Int(count); memory = Int(memoryCount); parallelism = Int(parallelismCount)
        }
        let resolved = try SDKKeyDerivationMapper.parameters(
            type: kdf ?? type,
            iterations: kdfIterations ?? iterations,
            memory: kdfMemory ?? memory,
            parallelism: kdfParallelism ?? parallelism
        )
        guard resolved == parameters else { throw AuthFlowError.invalidEncryptionParameters }
        guard let key, !key.isEmpty, let privateKey, !privateKey.isEmpty else { throw AuthFlowError.missingCryptoState }
        return StoredAuthAccount(
            userId: userID,
            email: email,
            serverBaseURL: serverBaseURL,
            kdfType: type,
            kdfIterations: iterations,
            kdfMemory: memory,
            kdfParallelism: parallelism,
            encryptedUserKey: key,
            encryptedPrivateKey: privateKey,
            isBiometricUnlockEnabled: false
        )
    }
}
