import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var store: RecentWorkspaceStore
    let appDelegate: AppDelegate
    let controller: CommandPaletteWindowController
    let initialFocus: CommandPaletteFocus

    private let source = CommandPaletteSource()

    @State private var search = ""
    @State private var sections: [CommandPaletteSection] = []
    @State private var selectedID: String?
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            searchFocused = true
            installKeyMonitorIfNeeded()
            refreshSections()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: search) {
            refreshSections()
        }
        .onChange(of: store.items) {
            refreshSections()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            TextField("Search workspaces and commands", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 5)

                        ForEach(section.entries) { entry in
                            row(entry)
                                .id(entry.id)
                                .onTapGesture {
                                    selectedID = entry.id
                                }
                                .onTapGesture(count: 2) {
                                    activate(entry, keepsOpen: false)
                                }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: selectedID) {
                if let selectedID {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private func row(_ entry: CommandPaletteEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.iconName)
                .font(.system(size: 18))
                .frame(width: 22, height: 22)
                .foregroundStyle(entry.isEnabled ? Color.secondary : Color.gray.opacity(0.45))

            Text(entry.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 14)
        .foregroundStyle(entry.isEnabled ? Color.primary : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selectedID == entry.id ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18) : .clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var flattenedEntries: [CommandPaletteEntry] {
        sections.flatMap(\.entries)
    }

    private var selectedEntry: CommandPaletteEntry? {
        guard let selectedID else { return nil }
        return flattenedEntries.first { $0.id == selectedID }
    }

    private func refreshSections() {
        Task {
            let resolved = await source.sections(
                workspaces: store.items,
                search: search,
                focus: initialFocus,
                hasActiveDocument: hasActiveDocumentWindow()
            )
            await MainActor.run {
                sections = resolved
                if selectedID == nil || !flattenedEntries.contains(where: { $0.id == selectedID }) {
                    selectedID = flattenedEntries.first?.id
                }
            }
        }
    }

    private func activateSelected(keepsOpen: Bool) {
        guard let selectedEntry else { return }
        activate(selectedEntry, keepsOpen: keepsOpen)
    }

    private func activate(_ entry: CommandPaletteEntry, keepsOpen: Bool) {
        switch entry {
        case .workspace(let item):
            if !keepsOpen {
                controller.closeAfterDispatch()
            }
            CommandPaletteDispatcher.dispatchRecentWorkspace(item, opener: appDelegate)
        case .command(let command, let isEnabled):
            guard isEnabled else {
                NSSound.beep()
                return
            }
            controller.closeAfterDispatch()
            DispatchQueue.main.async {
                command.handler(appDelegate: appDelegate)()
            }
        }
    }

    private func moveSelection(delta: Int) {
        let entries = flattenedEntries
        guard !entries.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in
            entries.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), entries.count - 1)
        selectedID = entries[nextIndex].id
    }

    private func hasActiveDocumentWindow() -> Bool {
        NSApp.orderedWindows.contains { window in
            guard window !== controller.window else { return false }
            return window.contentViewController is NSHostingController<DocumentWindowContent>
                || window.contentViewController is NSHostingController<FolderWindowContent>
                || window.contentViewController is NSHostingController<RemoteDocumentWindowContent>
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === controller.window else { return event }
            return handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = modifiers.contains(.command)

        if event.keyCode == 36 {
            activateSelected(keepsOpen: isCommand)
            return nil
        }
        if event.keyCode == 53 {
            controller.close()
            return nil
        }
        if event.keyCode == 126 {
            moveSelection(delta: -1)
            return nil
        }
        if event.keyCode == 125 {
            moveSelection(delta: 1)
            return nil
        }

        return event
    }
}
