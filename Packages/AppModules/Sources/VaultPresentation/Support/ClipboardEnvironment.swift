import Domain
import SwiftUI

private struct PasteboardClientKey: EnvironmentKey {
    static let defaultValue: (any PasteboardClient)? = nil
}

extension EnvironmentValues {
    var pasteboardClient: (any PasteboardClient)? {
        get { self[PasteboardClientKey.self] }
        set { self[PasteboardClientKey.self] = newValue }
    }
}
