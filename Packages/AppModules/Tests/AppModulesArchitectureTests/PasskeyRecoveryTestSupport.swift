import AutoFillContract
import BitwardenSDKAdapter
import Foundation

enum PasskeyRecoveryFixtureError: Error { case storage, write }

final class PasskeyRecoveryJournalFixture: PasskeyRegistrationRecoveryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PasskeyRegistrationRecoveryRecord] = []
    private var failing: Set<String> = []
    func fail(_ operation: String) { lock.withLock { _ = failing.insert(operation) } }
    var entries: [PasskeyRegistrationRecoveryRecord] { lock.withLock { values } }
    func records(requiring proof: ExtensionUnlockProof) throws -> [PasskeyRegistrationRecoveryRecord] {
        try lock.withLock { try check("read"); return values.filter { $0.account == proof.account } }
    }

    func reserve(_ record: PasskeyRegistrationRecoveryRecord, requiring proof: ExtensionUnlockProof) throws {
        try lock.withLock {
            try check("reserve"); try record.validate()
            guard record.account == proof.account else { throw PasskeyRegistrationRecoveryError.invalidRecord }
            guard !values.contains(where: { $0.account == proof.account }) else { throw PasskeyRegistrationRecoveryError.pendingMutation }
            values.append(record)
        }
    }

    func confirm(_ id: UUID, serverCipherID: String?, requiring proof: ExtensionUnlockProof) throws {
        try lock.withLock {
            try check("confirm")
            guard let i = values.firstIndex(where: { $0.mutationID == id && $0.account == proof.account }) else {
                throw PasskeyRegistrationRecoveryError.missingMutation
            }
            values[i].phase = .confirmed; values[i].serverCipherID = serverCipherID
        }
    }

    func remove(_ ids: Set<UUID>, requiring proof: ExtensionUnlockProof) throws {
        try lock.withLock { try check("remove"); values.removeAll { $0.account == proof.account && ids.contains(
            $0.mutationID
        ) } }
    }

    private func check(_ operation: String) throws { if failing.contains(operation) { throw PasskeyRecoveryFixtureError.storage } }
    static let proof = ExtensionUnlockProof(account: AutoFillAccountIdentity(
        userID: "user-1",
        serverBaseURL: URL(string: "https://vault.example.com")!
    ))
    static func record(target: String? = nil) -> PasskeyRegistrationRecoveryRecord {
        PasskeyRegistrationRecoveryRecord(
            account: proof.account,
            credentialID: Data([1]),
            relyingPartyIdentifier: "example.com",
            targetCipherID: target,
            originatingUnlockID: proof.unlockID
        )
    }
}

final class PasskeyRecoveryAccessFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var revoked = false
    private var writes = 0
    private var projections = 0
    var writeCount: Int { lock.withLock { writes } }
    var projectionCount: Int { lock.withLock { projections } }
    func revoke() { lock.withLock { revoked = true } }
    func check() throws { try lock.withLock { if revoked { throw CancellationError() } } }
    func write() -> CipherResponseDTO { lock.withLock { writes += 1 }; return AutoFillQuerySourceFixture.dto("saved") }
    func project(_ dto: CipherResponseDTO) { lock.withLock { projections += 1 } }
}
