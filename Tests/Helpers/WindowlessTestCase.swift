import AppKit
import XCTest

/// Base class for suites that drive real window-creating app flows (app
/// delegate windows, window controllers, restoration). The first use flips the
/// xctest process to a windowless activation policy, so windows the tested
/// code orders front never appear on the user's screen. Frames, controllers,
/// and all non-visual behavior keep working.
class WindowlessTestCase: XCTestCase {
    private static let makeProcessWindowless: Void = {
        NSApplication.shared.setActivationPolicy(.prohibited)
    }()

    override class func setUp() {
        super.setUp()
        _ = makeProcessWindowless
    }
}
