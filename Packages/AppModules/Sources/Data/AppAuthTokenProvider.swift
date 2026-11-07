import Foundation

/// Data owns bootstrap/commit authority, token lookup, refresh, expiry and retry decisions.
/// This type does not import or conform to SDK protocols; the SDK adapter bridges token callbacks.
/// A login bridge cannot access old credentials; its coordinator is created only after commit.
public actor AppAuthTokenProvider: SessionTokenProviding {
    public nonisolated let id = UUID()
    private let identityURL: URL
    private let keychainStore: AuthCredentialStore
    private let tokenService: any TokenRefreshing
    private let freshLoginProof: FreshLoginCommitProof?
    private var coordinator: TokenCoordinator?
    private var authorizationEpoch: UUID?
    private var isRevoked = false
    private var pendingExpiryHandler: (@Sendable () -> Void)?

    init(
        identityURL: URL,
        keychainStore: AuthCredentialStore,
        tokenService: any TokenRefreshing,
        scope: TokenScope? = nil,
        freshLoginProof: FreshLoginCommitProof? = nil,
        authorizationEpoch: UUID? = nil
    ) {
        self.identityURL = identityURL
        self.keychainStore = keychainStore
        self.tokenService = tokenService
        self.freshLoginProof = freshLoginProof
        if let scope {
            // Directly injected returning providers also capture at construction, never on a
            // later validation. Read failure leaves no epoch and all access fails closed.
            self.authorizationEpoch = authorizationEpoch ?? (
                try? keychainStore.returningUnlockEpoch(requiringScope: scope)
            )
            coordinator = TokenCoordinator(
                scope: scope,
                identityURL: identityURL,
                persistence: keychainStore.tokenPersistence(requiringEpoch: self.authorizationEpoch),
                refreshService: tokenService
            )
        }
    }

    public func setSessionExpiredHandler(_ handler: @escaping @Sendable () -> Void) async {
        guard !isRevoked else { return }
        pendingExpiryHandler = handler
        await coordinator?.setSessionExpiredHandler(handler)
    }

    /// Awaited by SessionRuntime before persistent cleanup. Neither bridge nor coordinator reopens.
    public func revoke() async {
        isRevoked = true
        pendingExpiryHandler = nil
        await coordinator?.revoke()
    }

    public func getAccessToken() async -> String? {
        guard !isRevoked, !Task.isCancelled, let coordinator else { return nil }
        guard (try? await validatedScope()) != nil else { return nil }
        let token = await coordinator.getAccessToken()
        guard !isRevoked, !Task.isCancelled else { return nil }
        guard (try? await validatedScope()) != nil else { return nil }
        return token
    }

    public func requireAccessToken() async throws -> String {
        _ = try await validatedScope()
        guard let coordinator else { throw CancellationError() }
        let token = try await coordinator.requireAccessToken()
        _ = try await validatedScope()
        return token
    }

    public func storeSession(account: StoredAuthAccount, tokens: TokenPair) async throws {
        guard !isRevoked, coordinator == nil,
              let freshLoginProof,
              identityURL == account.serverBaseURL.appendingPathComponent("identity") else { throw CancellationError() }
        try Task.checkCancellation()
        let committed = try keychainStore.saveSession(account: account, tokens: tokens, requiring: freshLoginProof)
        let record = committed.session
        authorizationEpoch = committed.publicationEpoch
        let bound = TokenCoordinator(
            scope: record.scope,
            identityURL: identityURL,
            persistence: keychainStore.tokenPersistence(requiringEpoch: committed.publicationEpoch),
            refreshService: tokenService,
            onSessionExpired: pendingExpiryHandler
        )
        coordinator = bound
        // No suspension or consumer-cancellation check after the atomic confirmed write.
        // The caller still validates/revokes its handoff capability before presenting a session;
        // UI cancellation must not misreport a committed login as an uncommitted storage failure.
    }

    /// Fresh credentials remain authorized only by the originally captured proof. Check after
    /// each suspended stage; commit still repeats this check under its own storage transaction.
    public func validateFreshLoginAuthority() throws {
        guard !isRevoked, coordinator == nil, let freshLoginProof else { throw CancellationError() }
        try keychainStore.validateFreshLoginAuthority(freshLoginProof)
    }

    public func validatedScope() async throws -> TokenScope {
        guard !isRevoked, !Task.isCancelled, let coordinator, let authorizationEpoch else { throw CancellationError() }
        let scope = try await coordinator.validatedScope()
        guard !isRevoked else { throw CancellationError() }
        try Task.checkCancellation()
        _ = try keychainStore.returningUnlockEpoch(requiringScope: scope, expectedEpoch: authorizationEpoch)
        return scope
    }

    public func validatedPublicationEpoch() async throws -> UUID {
        _ = try await validatedScope()
        guard let authorizationEpoch, !isRevoked else { throw CancellationError() }
        return authorizationEpoch
    }

    public func validatedSessionScope() async throws -> TokenScope {
        try await validatedScope()
    }
}
