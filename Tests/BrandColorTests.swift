import AppKit
import XCTest
@testable import Redmargin

final class BrandColorTests: XCTestCase {
    func testRedmarginRedMatchesRendererThemePalette() {
        XCTAssertEqual(resolvedHex(appearance: .aqua), "A64047")
        XCTAssertEqual(resolvedHex(appearance: .darkAqua), "C75259")
    }

    private func resolvedHex(appearance name: NSAppearance.Name) -> String {
        var hex = ""
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            guard let rgb = NSColor.redmarginRed.usingColorSpace(.sRGB) else {
                return XCTFail("redmarginRed did not resolve to sRGB")
            }
            hex = String(
                format: "%02X%02X%02X",
                Int(round(rgb.redComponent * 255)),
                Int(round(rgb.greenComponent * 255)),
                Int(round(rgb.blueComponent * 255))
            )
        }
        return hex
    }
}
