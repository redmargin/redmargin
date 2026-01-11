import SwiftUI

extension Notification.Name {
    static let toggleLineNumbers = Notification.Name("RedMargin.toggleLineNumbers")
    static let refreshDocument = Notification.Name("RedMargin.refreshDocument")
    static let showFindBar = Notification.Name("RedMargin.showFindBar")
    static let findNext = Notification.Name("RedMargin.findNext")
    static let findPrevious = Notification.Name("RedMargin.findPrevious")
}

extension URL {
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

@main
struct RedMarginApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("Redmargin")
                .frame(width: 200, height: 100)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appDelegate.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    RecentDocumentsMenu(appDelegate: appDelegate)
                }
                Divider()
            }

            // Remove Undo/Redo - read-only app
            CommandGroup(replacing: .undoRedo) { }

            // Keep only Copy from pasteboard (remove Cut, Paste)
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Divider()

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            // Add Find commands
            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    NotificationCenter.default.post(name: .showFindBar, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .findNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .findPrevious, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshDocument, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Toggle Line Numbers") {
                    NotificationCenter.default.post(name: .toggleLineNumbers, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }

            CommandGroup(replacing: .windowArrangement) { }
        }
    }
}

struct RecentDocumentsMenu: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Group {
            ForEach(appDelegate.recentDocuments, id: \.self) { url in
                Button(url.displayPath) {
                    appDelegate.openDocument(url)
                }
            }
            if appDelegate.recentDocuments.isEmpty {
                Text("No Recent Documents").foregroundColor(.secondary)
            } else {
                Divider()
                Button("Clear Menu") {
                    appDelegate.clearRecentDocuments()
                }
            }
        }
    }
}
