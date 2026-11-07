import AutoFillContract
import BitwardenSDKAdapter
import Domain
import Foundation

/// Narrow adapter-backed Data source, not a UI port or raw-client capability. SDK conversion
/// and policy stay in BitwardenSDKAdapter; this target does not import the upstream SDK.
/// Live implementations must guard every operation against the invocation's proof/resource.
public protocol AutoFillCredentialSource: Sendable {
    func readCache() throws -> SharedVaultCacheData
    func checkAccess() throws
    func decrypt(_ cipher: CipherResponseDTO) async throws -> SDKAutoFillCredentialView
    func oneTimeCode(seed: String, at date: Date) throws -> TimeBasedOneTimeCode
    func passkeys(in view: SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata]
}

struct URIQueryFilterResult {
    let items: [AutoFillLoginSummary]
    let isIncomplete: Bool
}

/// An immutable, per-operation index of the encrypted cache. It contains no decrypted values and
/// is discarded with the request. Duplicate IDs are deliberately excluded from lookup.
struct AutoFillCredentialSnapshot: Sendable {
    let cache: SharedVaultCacheData
    private let uniqueCiphersByID: [String: CipherResponseDTO]
    private let ambiguousIDs: Set<String>

    init(cache: SharedVaultCacheData) {
        self.cache = cache
        var unique: [String: CipherResponseDTO] = [:]
        var ambiguous: Set<String> = []
        for cipher in cache.ciphers {
            guard let id = cipher.id, !id.isEmpty, !ambiguous.contains(id) else { continue }
            if unique[id] == nil {
                unique[id] = cipher
            } else {
                unique[id] = nil
                ambiguous.insert(id)
            }
        }
        uniqueCiphersByID = unique
        ambiguousIDs = ambiguous
    }

    func uniqueCipher(id: String) -> CipherResponseDTO? {
        guard !ambiguousIDs.contains(id) else { return nil }
        return uniqueCiphersByID[id]
    }
}

/// Per-invocation credential orchestration. No decrypted vault or secret result is cached here.
/// Actor reentrancy never authorizes output: the source/cache are revalidated after each await.
public actor CredentialQuery {
    private let source: any AutoFillCredentialSource
    private let now: @Sendable () -> Date
    public init(source: any AutoFillCredentialSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source; self.now = now
    }

    public func logins(matching identifiers: [String] = [], requiringTOTP: Bool = false) async throws -> AutoFillCredentialList {
        let snapshot = AutoFillCredentialSnapshot(cache: try source.readCache())
        var items: [AutoFillLoginSummary] = [], failures = 0
        var views: [SDKAutoFillCredentialView] = []
        for dto in snapshot.cache.ciphers {
            try Task.checkCancellation()
            guard SDKVaultAccessPolicy.isEligibleForAutoFill(dto) else { continue }
            guard let id = dto.id, let current = snapshot.uniqueCipher(id: id) else { failures += 1; continue }
            do {
                let view = try await source.decrypt(dto)
                try Task.checkCancellation()
                try Self.requireCurrentAccess(to: view, matching: current, source: source)
                guard view.id == id, let login = view.login else { throw AutoFillOperationError.accessDenied }
                if requiringTOTP, login.totp?.isEmpty != false { continue }
                items.append(Self.summary(view: view, login: login, id: id))
                views.append(view)
            } catch is CancellationError { throw CancellationError() }
            catch {
                // Proof loss/cancellation is terminal; a damaged individual cipher remains visible.
                try source.checkAccess()
                failures += 1
            }
        }
        let filtered = try await Self.filterForAutoFill(items, matching: identifiers)
        let currentSnapshot = AutoFillCredentialSnapshot(cache: try source.readCache())
        for view in views {
            guard let id = view.id, let current = currentSnapshot.uniqueCipher(id: id), view.isCurrent(matching: current) else {
                throw AutoFillOperationError.accessDenied
            }
        }
        return AutoFillCredentialList(
            items: filtered.items,
            unavailableItemCount: failures,
            matchingEvaluationIncomplete: filtered.isIncomplete
        )
    }

    public nonisolated static func filter(_ items: [AutoFillLoginSummary], matching identifiers: [String]) -> [
        AutoFillLoginSummary
    ] {
        filterForQuery(items, matching: identifiers, context: URIQueryMatchingContext()).items
    }

    nonisolated static func filterForQuery(
        _ items: [AutoFillLoginSummary],
        matching identifiers: [String],
        context: URIQueryMatchingContext
    ) -> URIQueryFilterResult {
        guard !identifiers.isEmpty else { return URIQueryFilterResult(items: items, isIncomplete: false) }
        var matches: [AutoFillLoginSummary] = []
        for item in items {
            guard context.canContinue() else {
                return URIQueryFilterResult(items: matches, isIncomplete: !context.isCancelled)
            }
            var itemMatches = false
            for uri in item.uris {
                for identifier in identifiers {
                    guard context.canContinue() else {
                        return URIQueryFilterResult(items: matches, isIncomplete: !context.isCancelled)
                    }
                    if URIMatching.matches(
                        storedURI: uri.value,
                        matchType: uri.matchType,
                        requestURI: identifier,
                        using: context
                    ) {
                        itemMatches = true
                        break
                    }
                }
                if itemMatches { break }
            }
            if itemMatches { matches.append(item) }
        }
        return URIQueryFilterResult(items: matches, isIncomplete: context.isIncomplete)
    }

    private nonisolated static func filterForAutoFill(
        _ items: [AutoFillLoginSummary],
        matching identifiers: [String]
    ) async throws -> URIQueryFilterResult {
        let context = URIQueryMatchingContext(
            cancellationCheck: { withUnsafeCurrentTask { $0?.isCancelled ?? false } }
        )
        let result = filterForQuery(items, matching: identifiers, context: context)
        try Task.checkCancellation()
        return result
    }

    public func login(cipherId: String) async throws -> AutoFillLoginSummary {
        guard let view = try await cipherView(cipherId: cipherId), let login = view.login else { throw AutoFillOperationError.decryptFailed }
        return Self.summary(view: view, login: login, id: cipherId)
    }

    public func password(cipherId: String) async throws -> AutoFillPassword {
        guard let view = try await cipherView(cipherId: cipherId), let login = view.login,
              let username = login.username, let password = login.password else { throw AutoFillOperationError.decryptFailed }
        try Self.requireCurrentAccess(to: view, source: source)
        return AutoFillPassword(username: username, password: password)
    }

    public func oneTimeCode(cipherId: String) async throws -> TimeBasedOneTimeCode {
        guard let view = try await cipherView(cipherId: cipherId), let seed = view.login?.totp, !seed.isEmpty else {
            throw AutoFillOperationError.decryptFailed
        }
        // One bounded regeneration if local crypto/access checking crosses the period. Never
        // cache the seed/code, wait for a boundary or retry permission/metadata failures.
        for attempt in 0 ..< 2 {
            try Self.requireCurrentAccess(to: view, source: source)
            let date = now()
            let code = try source.oneTimeCode(seed: seed, at: date)
            guard code.generatedAt == date else { throw TimeBasedOneTimeCodeError.invalidMetadata }
            try Self.requireCurrentAccess(to: view, source: source)
            do { try code.validate(at: now()); return code }
            catch TimeBasedOneTimeCodeError.expired where attempt == 0 { continue }
        }
        throw TimeBasedOneTimeCodeError.expired
    }

    /// SDK-shaped only for existing registration/assertion adapters, never stored in picker state.
    public func cipherView(cipherId: String) async throws -> SDKAutoFillCredentialView? {
        let snapshot = AutoFillCredentialSnapshot(cache: try source.readCache())
        guard let dto = snapshot.uniqueCipher(id: cipherId) else {
            if snapshot.cache.ciphers.contains(where: { $0.id == cipherId }) { throw AutoFillOperationError.accessDenied }
            return nil
        }
        guard SDKVaultAccessPolicy.isEligibleForAutoFill(dto) else {
            throw AutoFillOperationError.accessDenied
        }
        let view = try await source.decrypt(dto)
        try Task.checkCancellation()
        guard view.id == cipherId else { throw AutoFillOperationError.accessDenied }
        try Self.requireCurrentAccess(to: view, matching: dto, source: source)
        let currentSnapshot = AutoFillCredentialSnapshot(cache: try source.readCache())
        try Self.requireCurrentAccess(to: view, matching: currentSnapshot.uniqueCipher(id: cipherId), source: source)
        return view
    }

    nonisolated static func requireCurrentAccess(
        to view: SDKAutoFillCredentialView,
        matching cipher: CipherResponseDTO,
        source: any AutoFillCredentialSource,
        forEditing: Bool = false
    ) throws {
        try source.checkAccess()
        guard view.isCurrent(matching: cipher) else { throw AutoFillOperationError.accessDenied }
        if forEditing {
            guard view.edit, cipher.edit != false, !cipher.hasUnrecognizedPayload else {
                throw AutoFillOperationError.accessDenied
            }
        }
    }

    nonisolated static func requireCurrentAccess(
        to view: SDKAutoFillCredentialView,
        matching cipher: CipherResponseDTO?,
        source: any AutoFillCredentialSource,
        forEditing: Bool = false
    ) throws {
        guard let cipher else { throw AutoFillOperationError.accessDenied }
        try requireCurrentAccess(to: view, matching: cipher, source: source, forEditing: forEditing)
    }

    public nonisolated static func requireCurrentAccess(
        to view: SDKAutoFillCredentialView,
        source: any AutoFillCredentialSource,
        forEditing: Bool = false
    ) throws {
        let cache = try source.readCache()
        guard view.isCurrent(in: cache.ciphers) else { throw AutoFillOperationError.accessDenied }
        if forEditing {
            guard let current = cache.ciphers.first(where: { $0.id == view.id }),
                  view.edit, current.edit != false, !current.hasUnrecognizedPayload else {
                throw AutoFillOperationError.accessDenied
            }
        }
    }

    private static func summary(view: SDKAutoFillCredentialView, login: SDKAutoFillCredentialView.Login, id: String) -> AutoFillLoginSummary {
        AutoFillLoginSummary(
            cipherId: id,
            name: view.name,
            username: login.username,
            hasTOTP: login.totp?.isEmpty == false,
            uris: login.uris.map { AutoFillLoginSummary.StoredURI(value: $0.value, matchType: $0.matchType) }
        )
    }
}
