@testable import AuthPresentation
import Data
import Foundation

final class MockIdentityTokenService: IdentityTokenService, @unchecked Sendable {
    var refreshOutcome: TokenRefreshOutcome = .retryable(.transport)
    private(set) var refreshCallCount = 0
    private(set) var requestCallCount = 0
    var beforeRefreshReturns: (@Sendable () async -> Void)?

    func requestToken(
        identityURL: URL,
        username: String,
        passwordHash: String,
        device: DeviceInfo,
        twoFactor: TwoFactorSubmission?
    ) async throws -> TokenRequestOutcome {
        requestCallCount += 1
        return .failure(message: "not used in these tests")
    }

    func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome {
        refreshCallCount += 1
        await beforeRefreshReturns?()
        return refreshOutcome
    }
}
