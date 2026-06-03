import AppKit
import SwiftUI

final class CommandPaletteWindowController: NSWindowController {
    static let frameAutosaveName = "CommandPalette"
    static let frameDefaultsKey = "RedMargin.CommandPaletteWindowFrame"

    private static let defaultSize = NSSize(width: 640, height: 420)

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

        panel.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = true
        panel.minSize = NSSize(width: 520, height: 320)
        installRootView(focus: focus)
        Self.configureFramePersistence(on: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func closeAfterDispatch() {
        if let window {
            Self.saveFrame(of: window)
        }
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
        restoreFrameAfterContentInstall()
    }

    private func positionIfNeeded() {
        guard let window else { return }
        let hasSavedFrame = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) != nil
        guard !hasSavedFrame else { return }

        Self.positionDefaultFrame(on: window)
    }

    static func configureFramePersistence(on window: NSWindow) {
        window.setFrameAutosaveName(frameAutosaveName)
        guard !restoreSavedFrame(on: window) else { return }

        positionDefaultFrame(on: window)
    }

    static func saveFrame(of window: NSWindow) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameDefaultsKey)
    }

    @discardableResult
    static func restoreSavedFrame(on window: NSWindow) -> Bool {
        guard let frameString = UserDefaults.standard.string(forKey: frameDefaultsKey) else {
            return false
        }
        let frame = NSRectFromString(frameString)
        guard !frame.isEmpty else {
            return false
        }
        window.setFrame(frame, display: false)
        return true
    }

    private func restoreFrameAfterContentInstall() {
        guard let window else { return }
        Self.restoreSavedFrame(on: window)
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            Self.restoreSavedFrame(on: window)
        }
    }

    private static func positionDefaultFrame(on window: NSWindow) {
        let screenFrame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - defaultSize.width / 2,
            y: screenFrame.maxY - screenFrame.height * 0.22 - defaultSize.height
        )
        window.setFrame(NSRect(origin: origin, size: defaultSize), display: false)
    }
}

extension CommandPaletteWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            Self.saveFrame(of: window)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            Self.saveFrame(of: window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            Self.saveFrame(of: window)
        }
    }
}
