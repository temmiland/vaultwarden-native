import Domain
import Foundation

#if os(iOS)
    import UIKit
    import UniformTypeIdentifiers
#else
    import AppKit
#endif

/// Keeps the selected URL private to PlatformServices and bounds its security-scoped grant to the
/// caller's operation. A future streaming upload can use the same API without moving file bytes
/// through presentation state.
private final class SystemImportedFile: ImportedFile, @unchecked Sendable {
    let fileName: String
    private let url: URL

    init(url: URL) {
        self.url = url
        fileName = url.lastPathComponent
    }

    func withSecurityScopedAccess<Value: Sendable>(
        _ operation: @Sendable (URL) async throws -> Value
    ) async throws -> Value {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try await operation(url)
    }
}

#if os(iOS)
    /// UIKit implementation for iOS. The document picker delegate is retained by this client until
    /// selection or cancellation completes the continuation exactly once.
    @MainActor
    public final class SystemFileImportClient: NSObject, FileImportClient, UIDocumentPickerDelegate {
        private var continuation: CheckedContinuation<URL?, any Error>?

        public func pickFile() async throws -> (any ImportedFile)? {
            guard continuation == nil else { throw FileImportClientError.pickerAlreadyPresented }
            guard let presenter = Self.topViewController() else {
                throw FileImportClientError.presentationUnavailable
            }

            let selectedURL: URL? = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
                picker.delegate = self
                presenter.present(picker, animated: true)
            }
            return selectedURL.map(SystemImportedFile.init(url:))
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(with: .success(urls.first))
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(with: .success(nil))
        }

        private func finish(with result: Result<URL?, any Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }

        private static func topViewController() -> UIViewController? {
            let root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?.rootViewController

            return topViewController(from: root)
        }

        private static func topViewController(from controller: UIViewController?) -> UIViewController? {
            if let presented = controller?.presentedViewController {
                return topViewController(from: presented)
            }
            if let navigation = controller as? UINavigationController {
                return topViewController(from: navigation.visibleViewController)
            }
            if let tab = controller as? UITabBarController {
                return topViewController(from: tab.selectedViewController)
            }
            return controller
        }
    }
#else
    /// AppKit implementation uses the sheet callback API, keeping the main run loop responsive while
    /// the user chooses a file.
    @MainActor
    public final class SystemFileImportClient: FileImportClient {
        public init() {}

        public func pickFile() async throws -> (any ImportedFile)? {
            guard let window = NSApp.keyWindow else { throw FileImportClientError.presentationUnavailable }

            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.title = "Choose a File to Send"

            let selectedURL: URL? = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
            return selectedURL.map(SystemImportedFile.init(url:))
        }
    }
#endif
