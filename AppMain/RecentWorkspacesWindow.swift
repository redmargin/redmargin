import AppKit
import SwiftUI

final class RecentWorkspacesWindowController: NSWindowController {
    private static weak var current: RecentWorkspacesWindowController?

    private let store: RecentWorkspaceStore
    private weak var appDelegate: AppDelegate?

    static func show(store: RecentWorkspaceStore, appDelegate: AppDelegate) {
        if let current {
            current.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = RecentWorkspacesWindowController(store: store, appDelegate: appDelegate)
        current = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(store: RecentWorkspaceStore, appDelegate: AppDelegate) {
        self.store = store
        self.appDelegate = appDelegate

        let window = NSWindow()
        super.init(window: window)

        let rootView = RecentWorkspacesView(
            store: store,
            appDelegate: appDelegate,
            controller: self
        )
        window.contentViewController = NSHostingController(rootView: rootView)
        window.title = "Recent Workspaces"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 600, height: 420)
        window.setFrameAutosaveName("RecentWorkspaces")

        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame RecentWorkspaces") != nil
        if !hasSavedFrame {
            window.setContentSize(NSSize(width: 760, height: 560))
            window.center()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func closeAfterOpening() {
        window?.orderOut(nil)
    }

    override func close() {
        super.close()
        Self.current = nil
    }
}
