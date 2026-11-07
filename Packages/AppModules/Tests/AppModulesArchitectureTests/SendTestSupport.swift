import Domain
import Foundation
@testable import SendPresentation
import Testing

@MainActor
final class MockPasteboard: PasteboardClient {
    private(set) var contents: String?
    func copySecret(_ value: String) { contents = value }
}

@MainActor
final class SendMockFileImportClient: FileImportClient {
    var fileToReturn: (any ImportedFile)?
    func pickFile() async throws -> (any ImportedFile)? { fileToReturn }
}
