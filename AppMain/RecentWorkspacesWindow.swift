import AppKit
import SwiftUI

final class RecentWorkspacesWindowController: NSWindowController {
    static let frameAutosaveName = "RecentWorkspaces"
    static let frameDefaultsKey = "RedMargin.RecentWorkspacesWindowFrame"

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
        Self.configureFramePersistence(on: window)
        window.delegate = self
    }

    static func configureFramePersistence(on window: NSWindow) {
        window.setFrameAutosaveName(frameAutosaveName)
        if let frameString = UserDefaults.standard.string(forKey: frameDefaultsKey) {
            let frame = NSRectFromString(frameString)
            if !frame.isEmpty {
                window.setFrame(frame, display: false)
                return
            }
        }

        window.setContentSize(NSSize(width: 760, height: 560))
        window.center()
    }

    static func saveFrame(of window: NSWindow) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameDefaultsKey)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func closeAfterOpening() {
        if let window {
            Self.saveFrame(of: window)
        }
        window?.orderOut(nil)
    }

    override func close() {
        super.close()
        Self.current = nil
    }
}

extension RecentWorkspacesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            Self.saveFrame(of: window)
        }
        Self.current = nil
    }
}
