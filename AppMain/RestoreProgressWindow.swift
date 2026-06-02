import AppKit
import SwiftUI

final class RestoreProgressWindowController: NSWindowController {
    init(message: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 126),
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
        panel.center()
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: String) {
        window?.contentViewController = NSHostingController(rootView: RestoreProgressView(message: message))
    }
}

private struct RestoreProgressView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
            Text("Remote windows will appear as their connections finish.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 320)
    }
}
