import AppKit
import SwiftUI

final class RestoreProgressWindowController: NSWindowController {
    init(message: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 132),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Restoring Windows"
        panel.tabbingMode = .disallowed
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.transient]
        panel.contentViewController = NSHostingController(rootView: RestoreProgressView(message: message))
        Self.centerOnVisibleScreen(panel)
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: String) {
        window?.contentViewController = NSHostingController(rootView: RestoreProgressView(message: message))
        if let window {
            Self.centerOnVisibleScreen(window)
        }
    }

    static func centerOnVisibleScreen(_ window: NSWindow, screen: NSScreen? = NSScreen.main) {
        guard let screen else {
            window.center()
            return
        }
        let frame = window.frame
        let visibleFrame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        ))
    }
}

private struct RestoreProgressView: View {
    let message: String

    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Remote windows will appear as their connections finish.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 440, alignment: .leading)
    }
}
