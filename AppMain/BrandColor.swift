import AppKit
import SwiftUI

extension NSColor {
    /// Redmargin brand red, taken from the renderer themes' margin red
    /// (#a64047 dark theme, #c75259 light theme). The lighter shade serves the
    /// dark appearance and vice versa so the text stays legible on both.
    static let redmarginRed = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0xC7 / 255, green: 0x52 / 255, blue: 0x59 / 255, alpha: 1)
            : NSColor(srgbRed: 0xA6 / 255, green: 0x40 / 255, blue: 0x47 / 255, alpha: 1)
    }
}

extension Color {
    static let redmarginRed = Color(nsColor: .redmarginRed)
}
