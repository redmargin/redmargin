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

    /// Gutter palette mirrored from `WebRenderer/styles/dark.css`
    /// (`--gutter-added` / `--gutter-deleted`); there is no shared token
    /// across the JS/Swift boundary, so a renderer palette change must be
    /// mirrored here by hand.
    static let gutterAdded = Color(red: 0x5C / 255, green: 0xB8 / 255, blue: 0x5C / 255)
    static let gutterDeleted = Color(red: 0xD4 / 255, green: 0x6A / 255, blue: 0x6A / 255)
}
