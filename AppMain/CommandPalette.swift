import AppKit
import Foundation
import RedmarginLib

enum AppCommand: CaseIterable, Hashable, Identifiable {
    case openFile
    case openRemote
    case recentWorkspaces
    case commandPalette
    case settings
    case findInPage
    case findNext
    case findPrevious
    case refresh
    case print
    case exportPDF
    case toggleSidebar
    case toggleHiddenFiles
    case toggleGutter
    case toggleLineNumbers
    case toggleGitIndicators
    case textWidth(TextWidth)
    case contentWidth(ContentWidth)
    case closeWindow
    case minimizeWindow
    case quit

    static var allCases: [AppCommand] {
        [
            .openFile,
            .openRemote,
            .recentWorkspaces,
            .commandPalette,
            .settings,
            .findInPage,
            .findNext,
            .findPrevious,
            .refresh,
            .print,
            .exportPDF,
            .toggleSidebar,
            .toggleHiddenFiles,
            .toggleGutter,
            .toggleLineNumbers,
            .toggleGitIndicators
        ]
        + TextWidth.allCases.map(AppCommand.textWidth)
        + ContentWidth.allCases.map(AppCommand.contentWidth)
        + [.closeWindow, .minimizeWindow, .quit]
    }

    var id: String { title }

    var title: String {
        switch self {
        case .openFile: return "Open File"
        case .openRemote: return "Open Remote"
        case .recentWorkspaces: return "Recent Workspaces"
        case .commandPalette: return "Command Palette"
        case .settings: return "Settings"
        case .findInPage: return "Find in Page"
        case .findNext: return "Find Next"
        case .findPrevious: return "Find Previous"
        case .refresh: return "Refresh"
        case .print: return "Print"
        case .exportPDF: return "Export PDF"
        case .toggleSidebar: return "Toggle Sidebar"
        case .toggleHiddenFiles: return "Toggle Hidden Files"
        case .toggleGutter: return "Toggle Gutter"
        case .toggleLineNumbers: return "Toggle Line Numbers"
        case .toggleGitIndicators: return "Toggle Git Indicators"
        case .textWidth(let value): return "Text Width: \(value.rawValue.capitalized)"
        case .contentWidth(let value): return "Block Width: \(value.rawValue.capitalized)"
        case .closeWindow: return "Close Window"
        case .minimizeWindow: return "Minimize Window"
        case .quit: return "Quit Redmargin"
        }
    }

    var keyEquivalent: String? {
        switch self {
        case .openFile: return "⌘O"
        case .openRemote: return "⇧⌘O"
        case .recentWorkspaces: return "⌘P"
        case .commandPalette: return "⇧⌘P"
        case .settings: return "⌘,"
        case .findInPage: return "⌘F"
        case .findNext: return "⌘G"
        case .findPrevious: return "⇧⌘G"
        case .refresh: return "⌘R"
        case .print: return "⌥⌘P"
        case .exportPDF: return "⌘E"
        case .toggleSidebar: return "⌘1"
        case .toggleHiddenFiles: return "⇧⌘."
        case .toggleGutter: return "⌥⌘G"
        case .toggleLineNumbers: return "⌘L"
        case .toggleGitIndicators: return "⇧⌘I"
        case .closeWindow: return "⌘W"
        case .minimizeWindow: return "⌘M"
        case .quit: return "⌘Q"
        case .textWidth, .contentWidth: return nil
        }
    }

    var iconName: String {
        switch self {
        case .openFile: return "doc"
        case .openRemote: return "network"
        case .recentWorkspaces: return "clock.arrow.circlepath"
        case .commandPalette: return "command"
        case .settings: return "gearshape"
        case .findInPage, .findNext, .findPrevious: return "magnifyingglass"
        case .refresh: return "arrow.clockwise"
        case .print: return "printer"
        case .exportPDF: return "square.and.arrow.up"
        case .toggleSidebar: return "sidebar.left"
        case .toggleHiddenFiles: return "eye"
        case .toggleGutter: return "rectangle.lefthalf.inset.filled"
        case .toggleLineNumbers: return "list.number"
        case .toggleGitIndicators: return "arrow.triangle.branch"
        case .textWidth: return "text.alignleft"
        case .contentWidth: return "rectangle.arrowtriangle.2.outward"
        case .closeWindow: return "xmark"
        case .minimizeWindow: return "minus"
        case .quit: return "power"
        }
    }

    var requiresActiveDocument: Bool {
        switch self {
        case .findInPage, .findNext, .findPrevious, .refresh, .print, .exportPDF,
             .toggleSidebar, .toggleHiddenFiles, .toggleGutter, .toggleLineNumbers,
             .toggleGitIndicators, .textWidth, .contentWidth:
            return true
        default:
            return false
        }
    }

    func handler(appDelegate: AppDelegate) -> () -> Void {
        {
            switch self {
            case .openFile:
                appDelegate.showOpenPanel()
            case .openRemote:
                appDelegate.showOpenRemoteSheet(nil)
            case .recentWorkspaces:
                appDelegate.showRecentWorkspaces(nil)
            case .commandPalette:
                appDelegate.showCommandPalette()
            case .settings:
                appDelegate.showPreferences(nil)
            case .findInPage:
                appDelegate.showFindBar(nil)
            case .findNext:
                appDelegate.findNext(nil)
            case .findPrevious:
                appDelegate.findPrevious(nil)
            case .refresh:
                appDelegate.refreshDocument(nil)
            case .print:
                appDelegate.printDocument(nil)
            case .exportPDF:
                appDelegate.exportDocument(nil)
            case .toggleSidebar:
                appDelegate.toggleSidebar(nil)
            case .toggleHiddenFiles:
                appDelegate.toggleHiddenFiles(nil)
            case .toggleGutter:
                appDelegate.toggleGutter(nil)
            case .toggleLineNumbers:
                appDelegate.toggleLineNumbers(nil)
            case .toggleGitIndicators:
                appDelegate.toggleGitIndicators(nil)
            case .textWidth(let value):
                let item = NSMenuItem()
                item.representedObject = value.rawValue
                appDelegate.setTextWidth(item)
            case .contentWidth(let value):
                let item = NSMenuItem()
                item.representedObject = value.rawValue
                appDelegate.setContentWidth(item)
            case .closeWindow:
                NSApp.keyWindow?.performClose(nil)
            case .minimizeWindow:
                NSApp.keyWindow?.performMiniaturize(nil)
            case .quit:
                NSApp.terminate(nil)
            }
        }
    }
}

struct CommandPaletteEntry: Identifiable, Hashable {
    let command: AppCommand
    let isEnabled: Bool

    var id: String { command.id }
    var title: String { command.title }
    var subtitle: String { command.keyEquivalent ?? "" }
    var iconName: String { command.iconName }
}

actor CommandPaletteSource {
    func entries(search: String, hasActiveDocument: Bool) -> [CommandPaletteEntry] {
        let query = PaletteSearchQuery(search)
        return AppCommand.allCases
            .filter { command in
                query.isEmpty || query.matches(commandTitle: command.title)
            }
            .map { command in
                CommandPaletteEntry(
                    command: command,
                    isEnabled: !command.requiresActiveDocument || hasActiveDocument
                )
            }
    }
}
