import AppKit
import ObjectiveC
import XCTest

/// Base class for suites that drive real window-creating app flows (app
/// delegate windows, window controllers, restoration). The first use makes the
/// xctest process windowless: the activation policy drops to prohibited AND the
/// NSWindow ordering methods are replaced with no-ops, so windows the tested
/// code "shows" never reach the screen. The policy alone proved insufficient;
/// the method replacement is what guarantees it. Frames, controllers, and all
/// non-visual behavior keep working; no test asserts on-screen visibility.
class WindowlessTestCase: XCTestCase {
    private static let makeProcessWindowless: Void = {
        NSApplication.shared.setActivationPolicy(.prohibited)

        let noOpWithSender: @convention(block) (NSWindow, Any?) -> Void = { _, _ in }
        replace(#selector(NSWindow.makeKeyAndOrderFront(_:)), with: noOpWithSender)

        let noOpBare: @convention(block) (NSWindow) -> Void = { _ in }
        replace(#selector(NSWindow.orderFrontRegardless), with: noOpBare)

        let noOpOrder: @convention(block) (NSWindow, Int, Int) -> Void = { _, _, _ in }
        replace(#selector(NSWindow.order(_:relativeTo:)), with: noOpOrder)
    }()

    private static func replace(_ selector: Selector, with block: Any) {
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
            preconditionFailure("WindowlessTestCase: NSWindow does not respond to \(selector)")
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    override class func setUp() {
        super.setUp()
        _ = makeProcessWindowless
    }
}
