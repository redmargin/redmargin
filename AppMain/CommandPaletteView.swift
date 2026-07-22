import AppKit
import SwiftUI

struct CommandPaletteView: View {
    let appDelegate: AppDelegate
    let controller: CommandPaletteWindowController

    private let source = CommandPaletteSource()

    @State private var search = ""
    @State private var entries: [CommandPaletteEntry] = []
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
            refreshEntries()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: search) {
            refreshEntries()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            TextField("Search commands", text: $search)
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
                    ForEach(entries) { entry in
                        row(entry)
                            .id(entry.id)
                            .onTapGesture {
                                selectedID = entry.id
                            }
                            .onTapGesture(count: 2) {
                                activate(entry)
                            }
                    }
                }
                .padding(.vertical, 8)
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

    private var selectedEntry: CommandPaletteEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }

    private func refreshEntries() {
        Task {
            let resolved = await source.entries(
                search: search,
                hasActiveDocument: hasActiveDocumentWindow()
            )
            await MainActor.run {
                entries = resolved
                if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                    selectedID = entries.first?.id
                }
            }
        }
    }

    private func activateSelected() {
        guard let selectedEntry else { return }
        activate(selectedEntry)
    }

    private func activate(_ entry: CommandPaletteEntry) {
        guard entry.isEnabled else {
            NSSound.beep()
            return
        }
        controller.closeAfterDispatch()
        DispatchQueue.main.async {
            entry.command.handler(appDelegate: appDelegate)()
        }
    }

    private func moveSelection(delta: Int) {
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
        if event.keyCode == 36 {
            activateSelected()
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
