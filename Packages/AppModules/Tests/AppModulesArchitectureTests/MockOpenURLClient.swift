import Domain
import Foundation

@MainActor
final class MockOpenURLClient: OpenURLClient {
    private(set) var openedURLs: [URL] = []
    var shouldFail = false

    func open(_ url: URL) async throws {
        guard !shouldFail else { throw OpenURLClientError.unableToOpen }
        openedURLs.append(url)
    }
}
