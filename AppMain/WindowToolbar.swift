import AppKit
import ObjectiveC

final class RedmarginWindowToolbar: NSObject, NSToolbarDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("RedmarginWindowToolbar")
    private static let recentWorkspacesIdentifier = NSToolbarItem.Identifier("recentWorkspaces")
    private static var associationKey: UInt8 = 0

    static func install(on window: NSWindow) {
        let delegate = RedmarginWindowToolbar()
        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true

        objc_setAssociatedObject(
            window,
            &associationKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        window.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.recentWorkspacesIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.recentWorkspacesIdentifier, .flexibleSpace, .space]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.recentWorkspacesIdentifier else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent Workspaces")
        item.label = "Recent Workspaces"
        item.paletteLabel = "Recent Workspaces"
        item.toolTip = "Show Recent Workspaces (⌘P)"
        item.target = nil
        item.action = #selector(AppDelegate.showRecentWorkspaces(_:))
        return item
    }
}
