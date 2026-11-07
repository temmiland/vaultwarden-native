import BitwardenSdk

/// The only SDK-specific part of the app token bridge. Token ownership/refresh decisions stay
/// in Data; the callback has no persistent state and cannot create or reopen an authority.
public final class SDKManagedTokenAdapter: ClientManagedTokens {
    private let accessToken: @Sendable () async -> String?

    public init(accessToken: @escaping @Sendable () async -> String?) {
        self.accessToken = accessToken
    }

    public func getAccessToken() async -> String? {
        guard !Task.isCancelled else { return nil }
        let token = await accessToken()
        guard !Task.isCancelled else { return nil }
        return token
    }
}
