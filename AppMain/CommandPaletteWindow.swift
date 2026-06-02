import AppKit
import SwiftUI

final class CommandPaletteWindowController: NSWindowController {
    private static weak var current: CommandPaletteWindowController?

    private let store: RecentWorkspaceStore
    private let appDelegate: AppDelegate
    private var focus: CommandPaletteFocus

    static func show(store: RecentWorkspaceStore, appDelegate: AppDelegate, focus: CommandPaletteFocus) {
        if let current {
            current.focus = focus
            current.installRootView(focus: focus)
            current.positionIfNeeded()
            current.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = CommandPaletteWindowController(store: store, appDelegate: appDelegate, focus: focus)
        current = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(store: RecentWorkspaceStore, appDelegate: AppDelegate, focus: CommandPaletteFocus) {
        self.store = store
        self.appDelegate = appDelegate
        self.focus = focus

        let panel = NSPanel()
        super.init(window: panel)

        panel.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = true
        panel.setFrameAutosaveName("CommandPalette")
        panel.setContentSize(NSSize(width: 640, height: 420))
        positionIfNeeded()
        installRootView(focus: focus)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func closeAfterDispatch() {
        window?.orderOut(nil)
    }

    override func close() {
        super.close()
        Self.current = nil
    }

    private func installRootView(focus: CommandPaletteFocus) {
        window?.contentViewController = NSHostingController(
            rootView: CommandPaletteView(
                store: store,
                appDelegate: appDelegate,
                controller: self,
                initialFocus: focus
            )
        )
    }

    private func positionIfNeeded() {
        guard let window else { return }
        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame CommandPalette") != nil
        guard !hasSavedFrame else { return }

        let screenFrame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = NSSize(width: 640, height: 420)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - screenFrame.height * 0.22 - size.height
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
