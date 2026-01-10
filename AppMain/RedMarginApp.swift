import SwiftUI

extension Notification.Name {
    static let toggleLineNumbers = Notification.Name("RedMargin.toggleLineNumbers")
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

            CommandGroup(after: .toolbar) {
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
