import AutoFillContract
import AutoFillData
import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation

/// Synthetic SDK models only. No Client, FFI, network, OS prompts or sleeps.
final class AutoFillQuerySourceFixture: AutoFillCredentialSource, @unchecked Sendable {
    private let lock = NSLock()
    private var cache: SharedVaultCacheData
    private var views: [String: CipherView]
    private var failedIDs: Set<String> = []
    private var denied = false
    private var gate: AuthOperationTestGate?
    private var decrypted: [String] = []
    private var generatedSeeds: [String] = []
    private var credentials: [Fido2CredentialAutofillView] = []
    private var codeHook: (@Sendable () -> Void)?
    private var codePeriod: UInt32 = 30
    private var generationDates: [Date] = []
    private var cacheReadCount = 0

    init(ids: [String] = ["cipher-1"], gate: AuthOperationTestGate? = nil) {
        cache = SharedVaultCacheData(
            ciphers: ids.map(Self.dto),
            organizationKeys: [:],
            updatedAt: .distantPast,
            owner: AutoFillAccountIdentity(userID: "user-1", serverBaseURL: URL(string: "https://vault.example.com")!),
            revision: UUID()
        )
        views = Dictionary(ids.map { ($0, Self.view(id: $0)) }, uniquingKeysWith: { first, _ in first })
        self.gate = gate
    }

    var decryptedIDs: [String] { lock.withLock { decrypted } }
    var seeds: [String] { lock.withLock { generatedSeeds } }
    var dates: [Date] { lock.withLock { generationDates } }
    var cacheReads: Int { lock.withLock { cacheReadCount } }
    func setCodePeriod(_ value: UInt32) { lock.withLock { codePeriod = value } }
    func deny() { lock.withLock { denied = true } }
    func fail(_ id: String) { lock.withLock { _ = failedIDs.insert(id) } }
    func setView(_ view: CipherView, id: String = "cipher-1") { lock.withLock { views[id] = view } }
    func editCache(_ body: (inout SharedVaultCacheData) -> Void) { lock.withLock { body(&cache) } }
    func setPasskeys(_ value: [Fido2CredentialAutofillView]) { lock.withLock { credentials = value } }
    func onCode(_ hook: @escaping @Sendable () -> Void) { lock.withLock { codeHook = hook } }
    func readCache() throws -> SharedVaultCacheData {
        try Task.checkCancellation()
        return try lock.withLock {
            if denied { throw CancellationError() }
            cacheReadCount += 1
            return cache
        }
    }

    func checkAccess() throws {
        try Task.checkCancellation()
        try lock.withLock { if denied { throw CancellationError() } }
    }

    func decrypt(_ cipher: CipherResponseDTO) async throws -> SDKAutoFillCredentialView {
        let (view, fails, gate) = lock.withLock {
            decrypted.append(cipher.id ?? "")
            let result = (views[cipher.id ?? ""], failedIDs.contains(cipher.id ?? ""), self.gate)
            self.gate = nil
            return result
        }
        await gate?.pause() // deliberately noncooperative
        if fails || view == nil { throw AuthFixtureError.operationFailed }
        return SDKAutoFillCredentialView(legacyView: view!)
    }

    func oneTimeCode(seed: String, at date: Date) throws -> TimeBasedOneTimeCode {
        let (hook, period) = lock.withLock { generatedSeeds.append(seed); generationDates.append(date); return (
            codeHook,
            codePeriod
        ) }
        hook?()
        return TimeBasedOneTimeCode(code: "123456", period: period, generatedAt: date)
    }

    func passkeys(in view: SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata] {
        lock.withLock { credentials.map { SDKAutoFillPasskeyMetadata(legacyView: $0) } }
    }

    static func dto(_ id: String) -> CipherResponseDTO {
        CipherResponseDTO(
            id: id,
            organizationId: nil,
            folderId: nil,
            collectionIds: nil,
            type: Int(CipherType.login.rawValue),
            name: "encrypted-name",
            notes: nil,
            favorite: false,
            reprompt: 0,
            key: nil,
            login: CipherLoginDTO(
                username: "encrypted-user",
                password: "encrypted-password",
                passwordRevisionDate: nil,
                uris: nil,
                totp: nil,
                autofillOnPageLoad: nil,
                fido2Credentials: nil
            ),
            card: nil,
            identity: nil,
            secureNote: nil,
            sshKey: nil,
            organizationUseTotp: false,
            edit: true,
            viewPassword: true,
            attachments: nil,
            revisionDate: "1970-01-01T00:00:00.000Z",
            creationDate: "1970-01-01T00:00:00.000Z",
            deletedDate: nil,
            archivedDate: nil
        )
    }

    static func view(
        id: String = "cipher-1",
        seed: String? = "synthetic-seed",
        password: String? = "synthetic-password",
        hasPasskeys: Bool = false,
        reprompt: CipherRepromptType = .none
    ) -> CipherView {
        .fixture(
            id: id,
            login: LoginView(
                username: "fixture-user",
                password: password,
                passwordRevisionDate: nil,
                uris: [LoginUriView(uri: "https://example.com", match: .domain, uriChecksum: nil)],
                totp: seed,
                autofillOnPageLoad: nil,
                fido2Credentials: hasPasskeys ? [Fido2Credential(
                    credentialId: "encrypted-id",
                    keyType: "public-key",
                    keyAlgorithm: "ECDSA",
                    keyCurve: "P-256",
                    keyValue: "encrypted-key",
                    rpId: "encrypted-rp",
                    userHandle: nil,
                    userName: nil,
                    counter: "0",
                    rpName: nil,
                    userDisplayName: nil,
                    discoverable: "true",
                    creationDate: .distantPast
                )] : nil
            ),
            reprompt: reprompt
        )
    }

    static func passkey(id: UInt8 = 1, rp: String = "example.com") -> Fido2CredentialAutofillView {
        Fido2CredentialAutofillView(
            credentialId: Foundation.Data([id]),
            cipherId: "cipher-1",
            rpId: rp,
            userNameForUi: "fixture-user",
            userHandle: Foundation.Data(),
            hasCounter: false
        )
    }
}
