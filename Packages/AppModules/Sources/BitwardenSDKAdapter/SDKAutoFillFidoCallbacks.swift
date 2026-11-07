import BitwardenSdk
import Domain
import Foundation

/// The SDK callback objects live only in this adapter. Callers inject scoped access/crypto/write
/// operations; this module never depends on AutoFillData, platform prompts or shared storage.
public final class SDKAutoFillFidoCredentialStore: Fido2CredentialStore {
    private let views: [SDKAutoFillCredentialView]
    private let userID: String
    private let readAccess: @Sendable () throws -> Void
    private let checkAccess: @Sendable () throws -> Void
    private let metadata: @Sendable (SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata]
    private let save: (@Sendable (SDKAutoFillEncryptedCipher) async throws -> Void)?

    public init(
        views: [SDKAutoFillCredentialView],
        userID: String,
        readAccess: @escaping @Sendable () throws -> Void,
        checkAccess: @escaping @Sendable () throws -> Void,
        metadata: @escaping @Sendable (SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata],
        save: (@Sendable (SDKAutoFillEncryptedCipher) async throws -> Void)? = nil
    ) {
        self.views = views; self.userID = userID; self.readAccess = readAccess
        self.checkAccess = checkAccess; self.metadata = metadata; self.save = save
    }

    public func findCredentials(ids: [Foundation.Data]?, ripId: String, userHandle: Foundation.Data?) async throws -> [
        CipherView
    ] {
        try readAccess()
        guard !ripId.isEmpty else { throw SDKAutoFillFidoError.invalidRequest }
        var matches: [CipherView] = []
        for view in views {
            guard SDKVaultAccessPolicy.isEligibleForAutoFill(view.legacyView), view.hasPasskeys else { continue }
            let credentials = try metadata(view)
            let counts = Dictionary(grouping: credentials, by: \.credentialId).mapValues(\.count)
            let matching = credentials.filter { credential in
                credential.rpId == ripId && (ids.map { $0.isEmpty || $0.contains(credential.credentialId) } ?? true) &&
                    (userHandle == nil || userHandle == credential.userHandle)
            }
            guard matching.allSatisfy(
                { !$0.credentialId.isEmpty && $0.cipherId == view.id && counts[$0.credentialId] == 1 }
            ) else {
                throw SDKAutoFillFidoError.accessDenied
            }
            if !matching.isEmpty { matches.append(view.legacyView) }
        }
        try readAccess()
        return matches
    }

    public func allCredentials() async throws -> [CipherListView] { try checkAccess(); return [] }

    public func saveCredential(cred: EncryptionContext) async throws {
        try checkAccess()
        guard let save else { throw SDKAutoFillFidoError.saveUnavailable }
        let encrypted = SDKAutoFillEncryptedCipher(legacyCipher: cred.cipher, encryptedFor: cred.encryptedFor)
        guard !userID.isEmpty, cred.encryptedFor == userID, encrypted.allowsPasskeyRegistration else {
            throw SDKAutoFillFidoError.accessDenied
        }
        try await save(encrypted)
        // Deliberately not readAccess: our own successful projection changes the original UUID.
        try checkAccess()
    }
}

public final class SDKAutoFillFidoUserInterface: Fido2UserInterface {
    private let selected: SDKAutoFillCredentialView?
    private let target: SDKAutoFillCredentialView?
    private let relyingPartyIdentifier: String
    private let readAccess: @Sendable () throws -> Void
    private let checkAccess: @Sendable () throws -> Void
    private let requireCurrent: @Sendable (SDKAutoFillCredentialView, Bool) throws -> Void
    private let verification: any PasskeyUserVerifying
    private let verificationState = SDKPasskeyVerificationState()

    public init(
        selectedForAuthentication: SDKAutoFillCredentialView? = nil,
        targetForCreation: SDKAutoFillCredentialView? = nil,
        relyingPartyIdentifier: String,
        readAccess: @escaping @Sendable () throws -> Void,
        checkAccess: @escaping @Sendable () throws -> Void,
        requireCurrent: @escaping @Sendable (SDKAutoFillCredentialView, Bool) throws -> Void,
        verification: any PasskeyUserVerifying
    ) {
        selected = selectedForAuthentication; target = targetForCreation; self.relyingPartyIdentifier = relyingPartyIdentifier
        self.readAccess = readAccess; self.checkAccess = checkAccess; self.requireCurrent = requireCurrent; self.verification = verification
    }

    public func checkUser(options: CheckUserOptions, hint: UiHint) async throws -> CheckUserResult {
        try readAccess()
        try requireNoVerificationFailure()
        if options.requireVerification == .discouraged { return CheckUserResult(userPresent: true, userVerified: false) }
        let verified: Bool
        do {
            if verification.isVerificationAvailable() { verified = try await verification.verify(
                reason: "Sign in with your passkey"
            ) } else { verified = false }
        } catch let failure as PasskeyUserVerificationError {
            verificationState.record(failure)
            throw failure
        }
        try readAccess()
        // Preferred/required false is returned explicitly; the SDK decides whether it can proceed.
        return CheckUserResult(userPresent: true, userVerified: verified)
    }

    public func pickCredentialForAuthentication(availableCredentials: [CipherView]) async throws -> CipherViewWrapper {
        try readAccess()
        guard availableCredentials.count == 1, let candidate = availableCredentials.first, let selected,
              candidate.id == selected.id, SDKVaultAccessPolicy.isEligibleForAutoFill(candidate) else {
            throw SDKAutoFillFidoError.ambiguousSelection
        }
        try requireCurrent(selected, false)
        try requireCurrent(SDKAutoFillCredentialView(legacyView: candidate), false)
        try checkAccess()
        return CipherViewWrapper(cipher: candidate)
    }

    public func checkUserAndPickCredentialForCreation(options: CheckUserOptions, newCredential: Fido2CredentialNewView) async throws -> CheckUserAndPickCredentialForCreationResult {
        try readAccess()
        guard let target, target.allowsPasskeyRegistration, !relyingPartyIdentifier.isEmpty,
              newCredential.rpId == relyingPartyIdentifier else { throw SDKAutoFillFidoError.accessDenied }
        if target.id != nil { try requireCurrent(target, true) }
        let result = try await checkUser(options: options, hint: .requestExistingCredential(target.legacyView))
        try readAccess()
        if target.id != nil { try requireCurrent(target, true) }
        return CheckUserAndPickCredentialForCreationResult(
            cipher: CipherViewWrapper(cipher: target.legacyView),
            checkUserResult: result
        )
    }

    public func isVerificationEnabled() -> Bool {
        do {
            try checkAccess()
            try requireNoVerificationFailure()
            let enabled = verification.isVerificationAvailable()
            try checkAccess()
            return enabled
        } catch { return false }
    }

    /// FFI may wrap a Swift callback error. Preserve the non-secret, invocation-local cancellation
    /// even if the engine wraps it or returns output. It must not become preferred=false success.
    func withVerificationFailureMapping<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        try requireNoVerificationFailure()
        do {
            let value = try await operation()
            try requireNoVerificationFailure()
            return value
        } catch {
            try requireNoVerificationFailure()
            throw error
        }
    }

    private func requireNoVerificationFailure() throws {
        try verificationState.check()
    }
}

/// Only the redacted sticky error is mutable, always under this lock. No credential/context
/// or authorization is retained; the SDK callback owner itself remains checked Sendable.
private final class SDKPasskeyVerificationState: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: PasskeyUserVerificationError?
    func record(_ value: PasskeyUserVerificationError) { lock.withLock { failure = value } }
    func check() throws { if let value = lock.withLock({ failure }) { throw value } }
}
