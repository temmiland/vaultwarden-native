import SwiftUI

public extension View {
    /// Minimum window/sheet dimensions on macOS without imposing a desktop-width floor on iOS.
    func platformMinSize(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        #if os(macOS)
            frame(minWidth: width, minHeight: height)
        #else
            self
        #endif
    }
}
