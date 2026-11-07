import BitwardenSdk
import BitwardenSDKAdapter
import CryptoKit
import Data
import Domain
import Foundation
import Networking
@_spi(Testing) import SecurityStorage
import Testing

/// Opt-in only. A version here is the owner's deployment assertion, not an independently
/// attested image/version probe. Never use a real vault or copy credentials into test fixtures.
struct LiveServerConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let environment: ServerEnvironment
    let email: String
    let password: String
    let totp: String?
    let passkeyCipherID: CipherID
    var description: String { "LiveServerConfiguration(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: []) }

    /// Validates every opt-in/consent/required field before any store, SDK client or request exists.
    init(values: [String: String]) throws {
        guard values["VW_TEST_LIVE"] == "1",
              values["VW_TEST_ALLOW_WRITES"] == "isolated-synthetic-account",
              let version = values["VW_TEST_SERVER_VERSION"],
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil,
              let address = values["VW_TEST_SERVER_URL"], let url = URL(string: address),
              ServerURLPolicy.isPermitted(url),
              let email = values["VW_TEST_EMAIL"], !email.isEmpty,
              let password = values["VW_TEST_PASSWORD"], !password.isEmpty,
              let passkeyID = values["VW_TEST_PASSKEY_CIPHER_ID"], UUID(uuidString: passkeyID) != nil
        else { throw LiveContractFailure.configuration }
        let totp = values["VW_TEST_TOTP"].flatMap { $0.isEmpty ? nil : $0 }
        if let totp, totp.count != 6 || !totp.allSatisfy(\.isASCII) || !totp.allSatisfy(\.isNumber) {
            throw LiveContractFailure.configuration
        }
        environment = try ServerEnvironment(baseURL: url)
        self.email = email
        self.password = password
        self.totp = totp
        passkeyCipherID = CipherID(rawValue: passkeyID)
    }
}

enum LiveContractFailure: Error { case configuration, verification }

/// Stage-safe summary. Never reflects SDK/HTTP diagnostics, response bodies or credential values.
enum LiveContractDiagnostics {
    static func classify(_ error: any Error) -> String {
        switch error {
        case let failure as LiveContractFailure: "\(failure)"
        case let status as HTTPStatusError: "http-status-\(status.statusCode)"
        case let transport as URLError: "url-error-\(transport.code.rawValue)"
        case is CancellationError: "cancelled"
        case let authorization as SessionAuthorizationError: "session-authorization-\(authorization)"
        case let repository as AuthRepositoryError: "auth-repository-\(repository)"
        case let vault as VaultRepositoryError: "vault-repository-\(vault)"
        case let settings as SettingsRepositoryError:
            switch settings {
            case let .server(statusCode): "settings-server-\(statusCode)"
            default: "settings-repository"
            }
        case let send as SendRepositoryError:
            switch send {
            case let .server(statusCode): "send-server-\(statusCode)"
            default: "send-repository"
            }
        default: "unclassified-\(String(reflecting: type(of: error)))"
        }
    }
}

/// RFC 6238/4226 reference used only to check live SDK output; not a product code path.
enum TOTPReference {
    static func base32Decode(_ text: String) -> [UInt8]? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer: UInt32 = 0, bits = 0, output: [UInt8] = []
        for character in text.uppercased() where character != "=" {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> UInt32(bits)) & 0xFF))
            }
        }
        return output
    }

    static func code(secret: [UInt8], counter: UInt64, digits: Int) -> String {
        let message = withUnsafeBytes(of: counter.bigEndian) { Foundation.Data($0) }
        let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let value = (UInt32(mac[offset] & 0x7F) << 24) | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0 ..< digits { modulus *= 10 }
        let digitsText = String(value % modulus)
        return String(repeating: "0", count: digits - digitsText.count) + digitsText
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LiveServerContractTests {
    /// A disposable, opt-in loopback server only. The account and all keys are created for this
    /// run, never read from the owner's configuration. The container owner destroys the server.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VW_TEST_EPHEMERAL_LOOPBACK"] != nil))
    func disposableLocalServerContracts() async {
        var stage = "configuration"
        var session: AuthenticatedSession?
        var secondarySession: AuthenticatedSession?
        var sends: DefaultSendRepository?
        var sendID: SendID?
        var vault: DefaultVaultRepository?
        var secondaryVault: DefaultVaultRepository?
        var concurrentCipherID: CipherID?
        var directory: URL?
        do {
            let raw = try #require(ProcessInfo.processInfo.environment["VW_TEST_EPHEMERAL_LOOPBACK"])
            let url = try #require(URL(string: raw))
            guard url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
                  url.path.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw LiveContractFailure.configuration
            }
            let environment = try ServerEnvironment(baseURL: url)
            let email = "contract-\(UUID().uuidString.lowercased())@example.invalid"
            let password = UUID().uuidString + UUID().uuidString
            let kdf = Kdf.pbkdf2(iterations: 600_000)
            let client = Client(tokenProvider: LocalContractTokenProvider(), settings: ClientSettings(
                identityUrl: environment.identityURL.absoluteString, apiUrl: environment.apiURL.absoluteString,
                userAgent: "local-synthetic-contract", deviceType: .macOsDesktop,
                deviceIdentifier: UUID().uuidString, bitwardenClientVersion: "0.0.1", bitwardenPackageType: nil
            ))
            let keys = try client.auth().makeRegisterKeys(email: email, password: password, kdf: kdf)
            let http = URLSessionHTTPClient()
            func post(_ path: String, _ object: [String: Any]) async throws -> HTTPResponse {
                let response = try await http.send(HTTPRequest(
                    url: environment.identityURL.appendingPathComponent(path), method: .post,
                    headers: ["Content-Type": "application/json", "Accept": "application/json"],
                    body: try JSONSerialization.data(withJSONObject: object), redirectPolicy: .reject
                ))
                try response.requireSuccess()
                return response
            }
            stage = "registration-token"
            let verification = try await post("accounts/register/send-verification-email", ["email": email])
            let token = try JSONDecoder().decode(String.self, from: verification.body)
            stage = "registration"
            _ = try await post("accounts/register/finish", [
                "email": email, "emailVerificationToken": token, "kdf": 0, "kdfIterations": 600_000,
                "key": keys.encryptedUserKey, "masterPasswordHash": keys.masterPasswordHash,
                "keys": ["publicKey": keys.keys.public, "encryptedPrivateKey": keys.keys.private],
            ])
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("vw-long-send-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            directory = root
            let files = SensitiveTemporaryFileStore(rootURL: root.appendingPathComponent("transfers"))
            let store = AuthCredentialStore(
                keychain: AuthKeychainFixture(),
                sharedKeychain: AuthKeychainFixture(),
                sharedContainerURL: root
            )
            let repository = DefaultAuthRepository(persistence: store)
            let commands = DefaultAuthFlowService(
                httpClient: http,
                store: store,
                repository: repository,
                biometric: ReturningBiometricFixture(),
                deviceName: PasswordDeviceNameFixture(),
                applicationVersion: "synthetic-contract"
            )
            stage = "login"
            guard case let .unlocked(pending) = try await commands.passwordSignIn.signIn(
                email: email, password: password, environment: environment
            ), let active = try await commands.prepareHandoff(pending, onExpired: { _ in }) as? AuthenticatedSession else {
                throw LiveContractFailure.verification
            }
            session = active
            _ = try await repository.completeUnlock(active.account, sessionID: active.id)
            let recordingHTTP = LocalContractRecordingHTTP(base: http)
            let sendRepository = DefaultSendRepository(
                runtime: active.runtime,
                cryptography: SDKSendCryptography(crypto: active.sendCryptoService),
                http: recordingHTTP,
                temporaryFiles: files
            )
            sends = sendRepository
            let file = root.appendingPathComponent(String(repeating: "a", count: 200) + ".txt")
            try Foundation.Data("synthetic payload".utf8).write(to: file)
            var draft = SendDraft(contentKind: .file)
            draft.name = "synthetic long filename"
            draft.pickedFileName = file.lastPathComponent
            stage = "file-send-create"
            let created = try await sendRepository.save(draft, file: LiveContractFile(url: file))
            let item = try #require(created.first(where: { $0.name == draft.name }))
            sendID = item.id
            guard await recordingHTTP.encryptedFilenameLength > 255 else { throw LiveContractFailure.verification }
            stage = "file-send-reread"
            _ = try await sendRepository.load()
            let details = try await sendRepository.details(for: item.id)
            guard details.fileName == file.lastPathComponent else { throw LiveContractFailure.verification }
            stage = "file-send-delete"
            _ = try await sendRepository.delete(id: item.id)
            sendID = nil
            print("LOCAL SERVER: long encrypted filename create/read/delete passed")

            // Configure a fresh TOTP secret using only this synthetic account. The server rejects
            // reusing the activation time step, so the subsequent login waits for the next step.
            func authenticatedPost(_ path: String, _ object: [String: Any]) async throws -> HTTPResponse {
                let accessToken = try await active.runtime.requireAccessToken()
                let response = try await http.send(HTTPRequest(
                    url: environment.apiURL.appendingPathComponent(path), method: .post,
                    headers: ["Content-Type": "application/json", "Authorization": "Bearer \(accessToken)"],
                    body: try JSONSerialization.data(withJSONObject: object), redirectPolicy: .reject
                ))
                try response.requireSuccess()
                return response
            }
            stage = "totp-setup"
            let setupResponse = try await authenticatedPost(
                "two-factor/get-authenticator",
                ["masterPasswordHash": keys.masterPasswordHash]
            )
            let setup = try #require(JSONSerialization.jsonObject(with: setupResponse.body) as? [String: Any])
            let authenticator = try #require(setup["authenticator"] as? [String: Any])
            let secret = try #require(authenticator["key"] as? String)
            let verifyToken = try #require(setup["userVerificationToken"] as? String)
            let secretBytes = try #require(TOTPReference.base32Decode(secret))
            let activationBucket = UInt64(Date().timeIntervalSince1970) / 30
            let activationCode = TOTPReference.code(secret: secretBytes, counter: activationBucket, digits: 6)
            _ = try await authenticatedPost(
                "two-factor/authenticator",
                ["key": secret, "token": activationCode, "userVerificationToken": verifyToken]
            )
            stage = "totp-login"
            let nextBucket = TimeInterval((activationBucket + 1) * 30)
            let wait = max(0, nextBucket - Date().timeIntervalSince1970 + 1)
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            let secondRoot = root.appendingPathComponent("second-login")
            try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: false)
            let secondStore = AuthCredentialStore(
                keychain: AuthKeychainFixture(),
                sharedKeychain: AuthKeychainFixture(),
                sharedContainerURL: secondRoot
            )
            let secondRepository = DefaultAuthRepository(persistence: secondStore)
            let secondCommands = DefaultAuthFlowService(
                httpClient: http,
                store: secondStore,
                repository: secondRepository,
                biometric: ReturningBiometricFixture(),
                deviceName: PasswordDeviceNameFixture(),
                applicationVersion: "synthetic-contract"
            )
            guard case let .twoFactorRequired(challenge) = try await secondCommands.passwordSignIn.signIn(
                email: email, password: password, environment: environment
            ) else { throw LiveContractFailure.verification }
            let loginCode = TOTPReference.code(
                secret: secretBytes,
                counter: UInt64(Date().timeIntervalSince1970) / 30,
                digits: 6
            )
            guard case let .unlocked(confirmed) = try await challenge.submitTOTP(code: loginCode, remember: false) else {
                await challenge.revoke()
                throw LiveContractFailure.verification
            }
            guard let secondSession = try await secondCommands.prepareHandoff(confirmed, onExpired: { _ in }) as? AuthenticatedSession else {
                throw LiveContractFailure.verification
            }
            secondarySession = secondSession
            _ = try await secondRepository.completeUnlock(secondSession.account, sessionID: secondSession.id)
            print("LOCAL SERVER: login TOTP challenge passed")

            stage = "concurrent-cipher-setup"
            let firstVault = DefaultVaultRepository(
                source: active.makeVaultSource(httpClient: http), temporaryFiles: files
            )
            vault = firstVault
            try await firstVault.sync()
            var initialDraft = VaultItemDraft(kind: .login)
            let marker = "concurrent-contract-\(UUID().uuidString)"
            initialDraft.name = marker
            initialDraft.username = "synthetic"
            initialDraft.password = UUID().uuidString
            initialDraft.notes = "synthetic-baseline"
            let cipherID = try await firstVault.save(initialDraft)
            concurrentCipherID = cipherID

            let secondVault = DefaultVaultRepository(
                source: secondSession.makeVaultSource(httpClient: http), temporaryFiles: files
            )
            secondaryVault = secondVault
            try await secondVault.sync()
            stage = "concurrent-cipher-snapshot"
            var firstEdit = try await firstVault.makeDraft(for: cipherID)
            var secondEdit = try await secondVault.makeDraft(for: cipherID)
            guard firstEdit.name == marker, secondEdit.name == marker,
                  firstEdit.notes == "synthetic-baseline", secondEdit.notes == "synthetic-baseline"
            else { throw LiveContractFailure.verification }
            firstEdit.name = "\(marker)-first-device"
            secondEdit.notes = "synthetic-second-device-update"
            // Vaultwarden's stale-date guard intentionally tolerates one second of timestamp
            // skew. Let the shared base become observably old before both requests race.
            try await Task.sleep(nanoseconds: 2_100_000_000)
            stage = "concurrent-cipher-write"
            async let firstWrite = Self.captureCipherWrite(firstVault, draft: firstEdit)
            async let secondWrite = Self.captureCipherWrite(secondVault, draft: secondEdit)
            let (firstResult, secondResult) = await (firstWrite, secondWrite)
            let acceptedCount = [firstResult, secondResult].filter { $0 == .accepted }.count
            let staleRejectedCount = [firstResult, secondResult].filter { $0 == .rejected(status: 400) }.count
            guard acceptedCount == 1, staleRejectedCount == 1 else { throw LiveContractFailure.verification }

            stage = "concurrent-cipher-reread"
            try await firstVault.sync()
            let finalDraft = try await firstVault.makeDraft(for: cipherID)
            let firstWriteWon = finalDraft.name == "\(marker)-first-device" &&
                finalDraft.notes == "synthetic-baseline"
            let secondWriteWon = finalDraft.name == marker &&
                finalDraft.notes == "synthetic-second-device-update"
            guard firstWriteWon || secondWriteWon else { throw LiveContractFailure.verification }
            print("LOCAL SERVER: stale concurrent cipher write was rejected; the accepted field remained intact")

            stage = "device-revocation"
            let deviceRepository = DefaultSettingsRepository(runtime: secondSession.runtime, http: http)
            let firstDeviceID = try store.deviceIdentifier()
            let secondDeviceID = try secondStore.deviceIdentifier()
            stage = "device-list"
            let devices = try await deviceRepository.fetchDevices()
            guard firstDeviceID != secondDeviceID, devices.contains(where: { $0.id == firstDeviceID }),
                  devices.contains(where: { $0.id == secondDeviceID }) else { throw LiveContractFailure.verification }
            stage = "device-delete"
            do {
                try await deviceRepository.revokeDevice(id: firstDeviceID)
                throw LiveContractFailure.verification
            } catch SettingsRepositoryError.server(statusCode: 404) {
                // This Vaultwarden version exposes GET /devices, but not individual DELETE.
                // Never infer revocation from a failed request or remove the device locally.
            }
            stage = "device-list-after-rejected-delete"
            let remaining = try await deviceRepository.fetchDevices()
            guard remaining.contains(where: { $0.id == firstDeviceID }) else { throw LiveContractFailure.verification }
            await secondSession.revoke(.logout)
            secondarySession = nil
            print("LOCAL SERVER: unsupported individual device revocation detected safely")
        } catch {
            Issue.record(
                "LOCAL SERVER long-filename contract failed at \(stage) (\(LiveContractDiagnostics.classify(error)))"
            )
        }
        if let sends {
            if let sendID { do { _ = try await sends.delete(id: sendID) } catch { Issue.record(
                "LOCAL SERVER cleanup failed"
            ) } }
            await sends.lock()
        }
        if let vault, let concurrentCipherID {
            do {
                try await vault.sync()
                let detail = try await requireDetail(concurrentCipherID, from: vault)
                try await vault.delete(detail.context)
            } catch {
                Issue.record("LOCAL SERVER synthetic cipher cleanup failed")
            }
        }
        await vault?.lock()
        await secondaryVault?.lock()
        await session?.revoke(.logout)
        await secondarySession?.revoke(.logout)
        if let directory { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(
            "LOCAL SERVER local cleanup failed"
        ) } }
    }

    private static let validConfiguration = [
        "VW_TEST_LIVE": "1",
        "VW_TEST_ALLOW_WRITES": "isolated-synthetic-account",
        "VW_TEST_SERVER_URL": "https://vault.example.invalid/proxy",
        "VW_TEST_SERVER_VERSION": "1.34.3",
        "VW_TEST_EMAIL": "synthetic@example.invalid",
        "VW_TEST_PASSWORD": "synthetic-password-value",
        "VW_TEST_PASSKEY_CIPHER_ID": "00000000-0000-4000-8000-000000000001",
    ]

    @Test
    func acceptsCompleteSyntheticConfigurationWithoutExposingIt() throws {
        let configuration = try LiveServerConfiguration(values: Self.validConfiguration)
        #expect(configuration.environment.baseURL.absoluteString == "https://vault.example.invalid/proxy")
        #expect(configuration.totp == nil)
        var withTOTP = Self.validConfiguration
        withTOTP["VW_TEST_TOTP"] = "123456"
        #expect(try LiveServerConfiguration(values: withTOTP).totp == "123456")
        for rendered in [String(describing: configuration), String(reflecting: configuration)] {
            #expect(!rendered.contains("synthetic-password-value"))
            #expect(!rendered.contains("synthetic@example.invalid"))
        }
        #expect(Mirror(reflecting: configuration).children.isEmpty)
    }

    /// Each case changes exactly one field of an otherwise valid configuration.
    @Test
    func refusesEachUnapprovedMissingOrUnsafeField() {
        let invalidFields: [(String, String?)] = [
            ("VW_TEST_LIVE", nil), ("VW_TEST_LIVE", "true"),
            ("VW_TEST_ALLOW_WRITES", nil), ("VW_TEST_ALLOW_WRITES", "production"),
            ("VW_TEST_SERVER_VERSION", nil), ("VW_TEST_SERVER_VERSION", ""), ("VW_TEST_SERVER_VERSION", "latest"),
            ("VW_TEST_SERVER_VERSION", "1.34"),
            ("VW_TEST_SERVER_URL", nil), ("VW_TEST_SERVER_URL", "http://vault.example.invalid"),
            ("VW_TEST_SERVER_URL", "https://user:secret@vault.example.invalid"), ("VW_TEST_SERVER_URL", "not a url"),
            ("VW_TEST_EMAIL", nil), ("VW_TEST_EMAIL", ""),
            ("VW_TEST_PASSWORD", nil), ("VW_TEST_PASSWORD", ""),
            ("VW_TEST_PASSKEY_CIPHER_ID", nil), ("VW_TEST_PASSKEY_CIPHER_ID", "passkey"),
            ("VW_TEST_TOTP", "12345"), ("VW_TEST_TOTP", "12345a"), ("VW_TEST_TOTP", "١٢٣٤٥٦"),
        ]
        for (key, value) in invalidFields {
            var values = Self.validConfiguration
            values[key] = value
            #expect(throws: LiveContractFailure.configuration) {
                _ = try LiveServerConfiguration(values: values)
            }
        }
    }

    @Test
    func totpReferenceMatchesRFC6238SHA1Vectors() throws {
        let secret = Array("12345678901234567890".utf8)
        for (time, expected) in [
            (59, "94287082"), (1_111_111_109, "07081804"), (1_111_111_111, "14050471"),
            (1_234_567_890, "89005924"), (2_000_000_000, "69279037"), (20_000_000_000, "65353130"),
        ] as [(UInt64, String)] {
            #expect(TOTPReference.code(secret: secret, counter: time / 30, digits: 8) == expected)
        }
        #expect(TOTPReference.code(secret: secret, counter: 1, digits: 6) == "287082")
        let decoded = try #require(TOTPReference.base32Decode("JBSWY3DPEHPK3PXP"))
        #expect(decoded == Array("Hello!".utf8) + [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test
    func failureSummariesNeverReflectDiagnosticBodies() {
        let status = HTTPStatusError(response: HTTPResponse(
            statusCode: 400, headers: [:], body: Foundation.Data(#"{"message":"synthetic-secret-detail"}"#.utf8)
        ))
        #expect(LiveContractDiagnostics.classify(status) == "http-status-400")
        #expect(LiveContractDiagnostics.classify(CancellationError()) == "cancelled")
        #expect(LiveContractDiagnostics.classify(LiveContractFailure.verification) == "verification")
        #expect(LiveContractDiagnostics.classify(SendRepositoryError.server(statusCode: 500)) == "send-server-500")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VW_TEST_LIVE"] == "1"))
    func existingServerFlows() async {
        var stage = "configuration"
        var session: AuthenticatedSession?
        var vault: DefaultVaultRepository?
        var sends: DefaultSendRepository?
        var createdCipher: CipherID?
        var createdSends: [SendID] = []
        var files: SensitiveTemporaryFileStore?
        var root: URL?
        var passed = false
        do {
            let configuration = try LiveServerConfiguration(values: ProcessInfo.processInfo.environment)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("vaultwarden-contract-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
            )
            root = directory
            let temporaryFiles = SensitiveTemporaryFileStore(rootURL: directory.appendingPathComponent("transfers"))
            files = temporaryFiles
            let privateKeychain = AuthKeychainFixture()
            let store = AuthCredentialStore(
                keychain: privateKeychain, sharedKeychain: AuthKeychainFixture(),
                sharedContainerURL: directory
            )
            let http = URLSessionHTTPClient()
            let repository = DefaultAuthRepository(persistence: store)
            let commands = DefaultAuthFlowService(
                httpClient: http, store: store, repository: repository,
                biometric: ReturningBiometricFixture(), deviceName: PasswordDeviceNameFixture(),
                applicationVersion: "synthetic-contract"
            )
            stage = "login"
            var outcome = try await commands.passwordSignIn.signIn(
                email: configuration.email, password: configuration.password, environment: configuration.environment
            )
            if case let .twoFactorRequired(challenge) = outcome {
                stage = "login-totp"
                guard let code = configuration.totp else {
                    await challenge.revoke()
                    throw LiveContractFailure.configuration
                }
                outcome = try await challenge.submitTOTP(code: code, remember: false)
                print("SERVER CONTRACT: login-totp passed")
            } else {
                print("SERVER CONTRACT: login-totp NOT EXERCISED (account has no challenge)")
            }
            guard case let .unlocked(pending) = outcome else { throw LiveContractFailure.verification }
            stage = "handoff"
            let capability = try await commands.prepareHandoff(pending, onExpired: { _ in })
            guard let active = capability as? AuthenticatedSession else {
                await capability.revoke(.lock)
                throw LiveContractFailure.verification
            }
            session = active
            let unlocked = try await repository.completeUnlock(active.account, sessionID: active.id)
            guard unlocked.sessionID == active.id, unlocked.state == .unlocked(active.account) else {
                throw LiveContractFailure.verification
            }
            print("SERVER CONTRACT: login/handoff passed")

            // Exercise the real coordinator, including pre-request intent and committed rotation.
            // Expire only this test's in-memory record, not the owner's Keychain or server account.
            stage = "refresh"
            guard let before = try store.loadSession() else { throw LiveContractFailure.verification }
            try PrivateAuthSessionStore(keychain: privateKeychain).save(PersistedAuthSession(
                account: before.account, scope: before.scope,
                tokens: TokenPair(
                    accessToken: before.tokens.accessToken, refreshToken: before.tokens.refreshToken,
                    expiresAt: .distantPast, generation: before.tokens.generation, updatedAt: before.tokens.updatedAt
                )
            ))
            _ = try await active.runtime.requireAccessToken()
            guard let rotated = try store.loadSession(), rotated.tokens.generation > before.tokens.generation,
                  rotated.scope == before.scope, rotated.account == before.account,
                  rotated.tokens.expiresAt > Date() else { throw LiveContractFailure.verification }
            print("SERVER CONTRACT: refresh passed")

            let vaultRepository = DefaultVaultRepository(
                source: active.makeVaultSource(httpClient: http), temporaryFiles: temporaryFiles
            )
            vault = vaultRepository
            stage = "sync/preseeded-passkey-read"
            try await vaultRepository.sync()
            let initial = await vaultRepository.currentSnapshot()
            guard initial.warnings.isEmpty,
                  let preseeded = initial.details[configuration.passkeyCipherID],
                  !(try await vaultRepository.passkeys(for: preseeded.context)).isEmpty else {
                throw LiveContractFailure.verification
            }
            print("SERVER CONTRACT: sync/preseeded-passkey-read passed")

            stage = "cipher-create/totp"
            let marker = "native-contract-\(UUID().uuidString)"
            var draft = VaultItemDraft(kind: .login)
            draft.name = marker
            draft.notes = "Synthetic native contract note"
            draft.username = "synthetic"
            draft.password = UUID().uuidString
            draft.totpSeed = "JBSWY3DPEHPK3PXP"
            draft.uris = ["https://example.invalid"]
            let id = try await vaultRepository.save(draft)
            createdCipher = id
            var detail = try await requireDetail(id, from: vaultRepository)
            guard let secret = TOTPReference.base32Decode(draft.totpSeed) else { throw LiveContractFailure.verification }
            let firstBucket = UInt64(Date().timeIntervalSince1970) / 30
            let code = try await vaultRepository.oneTimeCode(for: detail.context)
            let lastBucket = UInt64(Date().timeIntervalSince1970) / 30
            let references = Set((firstBucket ... lastBucket).map {
                TOTPReference.code(secret: secret, counter: $0, digits: 6)
            })
            guard code.period == 30, references.contains(code.code) else { throw LiveContractFailure.verification }

            stage = "cipher-update"
            let created = detail.context
            var edit = try await vaultRepository.makeDraft(for: id)
            guard edit.name == marker, edit.password == draft.password, edit.username == draft.username,
                  edit.totpSeed == draft.totpSeed, edit.notes == draft.notes, edit.uris == draft.uris else {
                throw LiveContractFailure.verification
            }
            edit.name += "-updated"
            guard try await vaultRepository.save(edit) == id else { throw LiveContractFailure.verification }
            detail = try await requireDetail(id, from: vaultRepository)
            let reread = try await vaultRepository.makeDraft(for: id)
            guard detail.name == edit.name, detail.context.revision > created.revision,
                  reread.password == draft.password, reread.totpSeed == draft.totpSeed,
                  reread.notes == draft.notes, reread.uris == draft.uris else {
                throw LiveContractFailure.verification
            }
            print("SERVER CONTRACT: cipher-create/update/totp passed")

            stage = "attachment-roundtrip"
            let input = directory.appendingPathComponent("synthetic.txt")
            let contents = Foundation.Data("Synthetic native contract payload".utf8)
            try contents.write(to: input, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
            let file = LiveContractFile(url: input)
            try await vaultRepository.uploadAttachment(to: detail.context, file: file)
            detail = try await requireDetail(id, from: vaultRepository)
            guard let reference = detail.attachments.first(where: { $0.fileName == file.fileName })?.reference else {
                throw LiveContractFailure.verification
            }
            let downloaded = try await vaultRepository.downloadAttachment(reference, context: detail.context)
            guard try Foundation.Data(contentsOf: downloaded) == contents else { throw LiveContractFailure.verification }
            try await temporaryFiles.removeWorkDirectory(downloaded.deletingLastPathComponent())
            try await vaultRepository.deleteAttachment(reference, context: detail.context)
            detail = try await requireDetail(id, from: vaultRepository)
            guard detail.attachments.isEmpty else { throw LiveContractFailure.verification }
            print("SERVER CONTRACT: attachment-upload/download/delete passed")

            let sendRepository = DefaultSendRepository(
                runtime: active.runtime, cryptography: SDKSendCryptography(crypto: active.sendCryptoService),
                http: http, temporaryFiles: temporaryFiles
            )
            sends = sendRepository
            _ = try await sendRepository.load()
            for kind in [SendContentKind.text, .file] {
                stage = kind == .text ? "text-send" : "file-send"
                var send = SendDraft(contentKind: kind)
                send.name = "\(marker)-\(stage)"
                send.text = "Synthetic native contract text"
                let rows = try await sendRepository.save(send, file: kind == .file ? file : nil)
                guard let created = rows.first(where: { $0.name == send.name }) else {
                    throw LiveContractFailure.verification
                }
                createdSends.append(created.id)
                var edited = try await sendRepository.editDraft(for: created.id)
                edited.name += "-updated"
                _ = try await sendRepository.save(edited, file: nil)
                let sendDetail = try await sendRepository.details(for: created.id)
                guard sendDetail.name == edited.name else { throw LiveContractFailure.verification }
                let remaining = try await sendRepository.delete(id: created.id)
                guard !remaining.contains(where: { $0.id == created.id }) else { throw LiveContractFailure.verification }
                createdSends.removeAll { $0 == created.id }
                print("SERVER CONTRACT: \(stage)-create/update/delete passed")
            }
            stage = "cipher-delete"
            detail = try await requireDetail(id, from: vaultRepository)
            try await vaultRepository.delete(detail.context)
            createdCipher = nil
            try await vaultRepository.sync()
            guard (await vaultRepository.currentSnapshot()).details[id] == nil else { throw LiveContractFailure.verification }
            print("SERVER CONTRACT: cipher-delete passed")
            passed = true
        } catch {
            // Do not let test-framework error reflection print SDK/network/password diagnostics.
            Issue.record("SERVER CONTRACT failed at \(stage) (\(LiveContractDiagnostics.classify(error)))")
        }

        // Delete only confirmed IDs created by this run. Unknown acknowledgements require manual
        // inspection/disposal of the isolated account; no retry-create and no name-based sweep.
        var cleanupFailed = false
        if let sends {
            for id in createdSends {
                do { _ = try await sends.delete(id: id) }
                catch {
                    cleanupFailed = true
                    Issue.record("SERVER CONTRACT Send cleanup failed; inspect isolated account")
                }
            }
            await sends.lock()
        }
        if let vault {
            if let id = createdCipher {
                do { try await vault.delete(try await requireDetail(id, from: vault).context) }
                catch {
                    cleanupFailed = true
                    Issue.record("SERVER CONTRACT Cipher cleanup failed; inspect isolated account")
                }
            }
            await vault.lock()
        }
        await session?.revoke(.logout)
        if let files {
            do { try await files.removeStaleWorkDirectories() }
            catch {
                cleanupFailed = true
                Issue.record("SERVER CONTRACT local transfer cleanup failed")
            }
        }
        if let root {
            do { try FileManager.default.removeItem(at: root) }
            catch {
                cleanupFailed = true
                Issue.record("SERVER CONTRACT isolated test directory cleanup failed")
            }
        }
        // The runner accepts the contract only with this exact line; a skip never prints it.
        if passed, !cleanupFailed { print("SERVER CONTRACT: all stages passed") }
    }

    private func requireDetail(_ id: CipherID, from vault: DefaultVaultRepository) async throws -> VaultItemDetail {
        guard let detail = (await vault.currentSnapshot()).details[id] else { throw LiveContractFailure.verification }
        return detail
    }

    private static func captureCipherWrite(
        _ vault: DefaultVaultRepository,
        draft: VaultItemDraft
    ) async -> LocalContractWriteOutcome {
        do {
            _ = try await vault.save(draft)
            return .accepted
        } catch let status as HTTPStatusError {
            return .rejected(status: status.statusCode)
        } catch {
            return .failed
        }
    }
}

private enum LocalContractWriteOutcome: Sendable, Equatable {
    case accepted
    case rejected(status: Int)
    case failed
}

private struct LiveContractFile: ImportedFile {
    let url: URL
    var fileName: String { url.lastPathComponent }
    func withSecurityScopedAccess<Value: Sendable>(
        _ operation: @Sendable (URL) async throws -> Value
    ) async throws -> Value { try await operation(url) }
}

private final class LocalContractTokenProvider: ClientManagedTokens {
    func getAccessToken() async -> String? { nil }
}

private actor LocalContractRecordingHTTP: HTTPClient {
    private let base: URLSessionHTTPClient
    private(set) var encryptedFilenameLength = 0
    init(base: URLSessionHTTPClient) { self.base = base }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.path.hasSuffix("/sends/file/v2"), let body = request.body,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let file = object["file"] as? [String: Any], let name = file["fileName"] as? String {
            encryptedFilenameLength = name.utf8.count
        }
        return try await base.send(request)
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        try await base.upload(request, fromFile: fileURL)
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        try await base.download(request, to: destinationURL)
    }
}
