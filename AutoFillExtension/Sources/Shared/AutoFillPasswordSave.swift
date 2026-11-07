import AutoFillContract
import AutoFillData
import BitwardenSDKAdapter
import Data
import Domain
import Foundation
import Networking
import PlatformServices
import SecurityStorage

/// Saves only after explicit user confirmation. The shared durable mutation journal prevents a
/// transport timeout or a retired UI from silently reopening a potentially committed write.
enum AutoFillPasswordSave {
    static func save(
        title: String,
        username: String,
        password: String,
        uri: String,
        targetID: String?,
        session: ExtensionVaultSession
    ) async throws {
        guard let host = URL(string: uri)?.host, !host.isEmpty else {
            throw AutoFillOperationError.accessDenied
        }
        let domain = QuickTypeIdentityPolicy.domain(for: uri, matchType: .domain) ?? host
        let journal = try SharedAppGroup.makePasskeyRecoveryStore()
        guard try journal.records(requiring: session.proof).isEmpty else { throw PasskeyRegistrationError.recoveryRequired }
        _ = try session.readCache()
        let target: SDKAutoFillCredentialView?
        if let id = targetID {
            guard let value = try await session.credentials.cipherView(cipherId: id) else {
                throw AutoFillOperationError.accessDenied
            }
            try session.requireCurrentAccess(to: value, forEditing: true)
            guard value.login?.uris.contains(where: {
                URIMatching.matches(storedURI: $0.value, matchType: $0.matchType, requestURI: uri)
            }) == true else { throw AutoFillOperationError.accessDenied }
            target = value
        } else { target = nil }
        let encrypted = try await session.perform {
            try await $0.encryptPasswordSave(
                title: title,
                username: username,
                password: password,
                uri: uri,
                target: target
            )
        }
        _ = try session.readCache()
        if let target { try session.requireCurrentAccess(to: target, forEditing: true) }
        let environment = try SDKAutoFillAccountMapper.environment(for: session.accountInfo)
        let http = ExtensionHTTPClient(base: URLSessionHTTPClient(), session: session)
        let tokens = SharedTokenProvider(
            identityURL: environment.identityURL,
            store: try SharedAppGroup.makeTokenStore(),
            httpClient: http,
            unlockProof: session.proof
        )
        let service = SDKCipherService(
            httpClient: http,
            apiURL: environment.apiURL,
            userID: session.accountInfo.userId,
            accessToken: { await tokens.getAccessToken() },
            requireAccessToken: { try await tokens.requireAccessToken() }
        )
        let record = PasskeyRegistrationRecoveryRecord(
            account: session.proof.account, credentialID: Foundation.Data(), relyingPartyIdentifier: domain,
            targetCipherID: targetID, originatingUnlockID: session.proof.unlockID, kind: .password,
            passwordCiphertextHash: encrypted.passwordCiphertextHash
        )
        _ = try await session.registrationWrites.save(
            record: record, proof: session.proof, journal: journal,
            checkAccess: { try session.checkAccess() },
            write: {
                _ = try session.readCache()
                if let target { try session.requireCurrentAccess(to: target, forEditing: true) }
                return try await service.saveCredentialResponse(encrypted)
            },
            project: { dto in
                let view = try await session.perform { try await $0.decryptView(dto) }
                guard let id = dto.id, let login = view.login, login.username == username, login.password == password else {
                    throw AutoFillOperationError.saveFailed
                }
                let cache = try AutoFillVaultStore.cacheStore
                let receipt = try cache.upsertReturningReceipt(
                    dto,
                    for: session.proof.account,
                    requiringProof: session.proof,
                    cacheRevision: session.cacheRevision
                )
                // Strict existing URI modes stay in the interactive picker. A full sync repairs
                // their projection; never invent a broader identity during a password update.
                guard login.uris.contains(where: {
                    QuickTypeIdentityPolicy.domain(for: $0.value, matchType: $0.matchType) == domain
                }) else { return }
                let identity = CredentialIdentityDescriptor(
                    id: [id, "password", domain, ""].joined(separator: "|"), kind: .password,
                    serviceIdentifier: domain, user: username, label: view.name, credentialID: nil,
                    userHandle: nil, recordIdentifier: CipherID(rawValue: id)
                )
                let store = SystemCredentialIdentityStore()
                let coordinator = SharedAppGroup.identityMutationCoordinator(containerURL: SharedAppGroup.containerURL)
                try await coordinator.withExclusiveMutation {
                    try session.checkAccess()
                    try cache.requireCurrent(receipt, requiring: session.proof)
                    do {
                        try await store.addPasswordIdentity(identity)
                        try session.checkAccess()
                        try cache.requireCurrent(receipt, requiring: session.proof)
                    } catch {
                        try await store.removePasswordIdentity(identity)
                        throw error
                    }
                }
            }
        )
    }
}
