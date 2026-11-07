import Domain

extension AccountSession {
    public init(storedAccount account: StoredAuthAccount) throws {
        self.init(
            accountID: AccountID(rawValue: account.userId),
            email: account.email,
            environment: try Domain.ServerEnvironment(baseURL: account.serverBaseURL)
        )
    }
}
