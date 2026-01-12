import AppKit
import SwiftUI

public final class PreferencesWindowController: NSWindowController {
    public static let shared = PreferencesWindowController()

    private static let frameAutosaveName = "PreferencesWindow"

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Redmargin Settings"
        window.minSize = NSSize(width: 450, height: 300)
        window.maxSize = NSSize(width: 700, height: 500)

        super.init(window: window)

        let preferencesView = PreferencesView()
        let hostingView = NSHostingView(rootView: preferencesView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        containerView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        window.contentView = containerView

        window.setFrameAutosaveName(Self.frameAutosaveName)

        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}
