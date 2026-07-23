import AppKit
import RedmarginCore
import SwiftUI

struct RecentWorkspacesView: View {
    @ObservedObject var store: RecentWorkspaceStore
    let appDelegate: AppDelegate
    let controller: RecentWorkspacesWindowController

    @State private var search = ""
    @State private var tierFilter: RecentWorkspaceTierFilter = .all
    @State private var kindFilter: RecentWorkspaceKindFilter = .all
    @State private var pinnedOnly = false
    @State private var selectedID: UUID?
    @State private var localAvailability: [String: Bool] = [:]
    @State private var gitSummaries: [String: GitWorkspaceSummary] = [:]
    @State private var liveHosts: Set<String> = []
    @State private var scannedContextKey: Set<String> = []
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 420)
        .onAppear {
            searchFocused = true
            installKeyMonitorIfNeeded()
            selectFirstIfNeeded()
            refreshAvailability()
            refreshWorkspaceContext(force: true)
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: store.items) {
            refreshAvailability()
            refreshWorkspaceContext()
            selectFirstIfNeeded()
        }
        .onChange(of: search) {
            postFilterAccessibilityChange()
            selectFirstIfNeeded()
        }
        .onChange(of: tierFilter) {
            postFilterAccessibilityChange()
            selectFirstIfNeeded()
        }
        .onChange(of: kindFilter) {
            postFilterAccessibilityChange()
            selectFirstIfNeeded()
        }
        .onChange(of: pinnedOnly) {
            postFilterAccessibilityChange()
            selectFirstIfNeeded()
        }
        .onDeleteCommand(perform: removeSelected)
        .onMoveCommand(perform: moveSelection)
        .onExitCommand(perform: handleEscape)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Recent Workspaces")
                .font(.system(size: 22, weight: .semibold))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search recent workspaces")
                    .onSubmit { openSelected() }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .frame(height: 56)
        .padding(.horizontal, 20)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Text("Tier")
            RedSegmentedControl(
                options: RecentWorkspaceTierFilter.allCases.map { ($0.rawValue, $0) },
                selection: $tierFilter
            )
            .accessibilityLabel("Tier")
            .accessibilityValue(tierFilter.rawValue)

            Text("Kind")
            RedSegmentedControl(
                options: RecentWorkspaceKindFilter.allCases.map { ($0.rawValue, $0) },
                selection: $kindFilter
            )
            .accessibilityLabel("Kind")
            .accessibilityValue(kindFilter.rawValue)

            Spacer()

            Button {
                pinnedOnly.toggle()
            } label: {
                Image(systemName: pinnedOnly ? "pin.fill" : "pin")
                    .foregroundStyle(pinnedOnly ? Color.redmarginRed : Color.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Pinned only")
            .accessibilityLabel("Pinned only")
            .accessibilityValue(pinnedOnly ? "On" : "Off")
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(height: 36)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
        } else if visibleItems.isEmpty {
            noMatchesState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !visiblePinned.isEmpty {
                            sectionTitle("Pinned")
                            rows(visiblePinned)
                            Divider().padding(.leading, 20)
                        }

                        sectionTitle("Recent")
                        rows(visibleRecent)
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
    }

    private func rows(_ items: [RecentWorkspaceItem]) -> some View {
        ForEach(items) { item in
            RecentWorkspaceRowView(
                item: item,
                isSelected: selectedID == item.id,
                isFocused: selectedID == item.id,
                isUnavailable: isUnavailable(item),
                gitSummary: gitSummaries[item.storageKey],
                hasLiveConnection: item.remoteLocation.map { liveHosts.contains($0.host) } ?? false,
                onOpen: { open(item) },
                onRetry: { retry(item) },
                onPinToggle: { togglePin(item) },
                onRemove: { remove(item) },
                onLocate: { locate(item) }
            )
            .id(item.id)
            .padding(.horizontal, 8)
            .onTapGesture {
                selectedID = item.id
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Clear Missing") {
                store.clearMissingLocal()
                refreshAvailability()
            }
            .buttonStyle(.bordered)
            .disabled(!hasMissingLocal)

            Button("Clear All...") {
                confirmClearAll()
            }
            .buttonStyle(.bordered)
            .foregroundStyle(Color.redmarginRed)
            .disabled(store.items.isEmpty)

            Spacer()

            if selectedItem != nil {
                Text("1 selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open") {
                openSelected()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.redmarginRed)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(selectedItem == nil || selectedItem.map(isUnavailable) == true)
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 72))
                .foregroundStyle(.tertiary)
            Text("No Recent Workspaces")
                .font(.title3.weight(.semibold))
            Text("Open a file or folder to start building your recent list.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Open...") {
                    appDelegate.showOpenPanel()
                }
                Button("Open Remote...") {
                    appDelegate.showOpenRemoteSheet(nil)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Matches")
                .font(.title3.weight(.semibold))
            Text("Try a different search or filter.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleItems: [RecentWorkspaceItem] {
        store.filtered(search: search, tier: tierFilter, kind: kindFilter, pinnedOnly: pinnedOnly)
    }

    private var visiblePinned: [RecentWorkspaceItem] {
        visibleItems.filter(\.isPinned)
    }

    private var visibleRecent: [RecentWorkspaceItem] {
        visibleItems.filter { !$0.isPinned }
    }

    private var selectedItem: RecentWorkspaceItem? {
        guard let selectedID else { return nil }
        return visibleItems.first { $0.id == selectedID }
    }

    private var hasMissingLocal: Bool {
        store.items.contains { item in
            item.localURL != nil && isUnavailable(item)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
    }

    private func isUnavailable(_ item: RecentWorkspaceItem) -> Bool {
        if item.lastFailureReason != nil { return true }
        guard item.localURL != nil else { return false }
        return localAvailability[item.storageKey] == false
    }

    /// Loads git summaries for local folder rows and live-connection state for
    /// remote hosts. Repos scan concurrently. `force` bypasses the same-keys
    /// gate so reopening the window picks up fresh git state; store changes
    /// that keep the same folders and hosts (pinning, reopening) skip the scan.
    private func refreshWorkspaceContext(force: Bool = false) {
        let localFolders = store.items.filter { $0.kind == .localFolder && !$0.isLocalMissing }
        let remoteHosts = Set(store.items.compactMap { $0.remoteLocation?.host })
        let contextKey = Set(localFolders.map(\.storageKey)).union(remoteHosts)
        guard force || contextKey != scannedContextKey else { return }
        scannedContextKey = contextKey

        Task {
            let folderTargets = localFolders.compactMap { item in
                item.localURL.map { (key: item.storageKey, url: $0) }
            }
            let summaries = await withTaskGroup(
                of: (String, GitWorkspaceSummary?).self,
                returning: [String: GitWorkspaceSummary].self
            ) { group in
                for target in folderTargets {
                    group.addTask {
                        (target.key, await GitStatusProvider.shared.summary(for: target.url))
                    }
                }
                var result: [String: GitWorkspaceSummary] = [:]
                for await (key, summary) in group {
                    if let summary { result[key] = summary }
                }
                return result
            }

            var live: Set<String> = []
            for host in remoteHosts {
                if await SSHConnectionManager.shared.hasLiveConnection(host: host) {
                    live.insert(host)
                }
            }

            let resolvedLive = live
            await MainActor.run {
                gitSummaries = summaries
                liveHosts = resolvedLive
            }
        }
    }

    private func refreshAvailability() {
        var next = localAvailability
        for item in store.items where item.localURL != nil {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: item.localURL?.path ?? "", isDirectory: &isDirectory)
            next[item.storageKey] = exists && (item.kind != .localFolder || isDirectory.boolValue)
        }
        localAvailability = next
    }

    private func selectFirstIfNeeded() {
        if let selectedID, visibleItems.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = visibleItems.first?.id
    }

    private func openSelected() {
        guard let item = selectedItem else { return }
        open(item)
    }

    private func open(_ item: RecentWorkspaceItem) {
        if isUnavailable(item), item.localURL != nil {
            NSSound.beep()
            return
        }

        if item.remoteLocation != nil {
            retry(item)
            return
        }

        appDelegate.openRecentWorkspace(item)
        controller.closeAfterOpening()
    }

    private func retry(_ item: RecentWorkspaceItem) {
        Task {
            let succeeded = await appDelegate.retryRecentWorkspace(item)
            if succeeded {
                await MainActor.run {
                    controller.closeAfterOpening()
                }
            } else {
                await MainActor.run {
                    refreshAvailability()
                }
            }
        }
    }

    private func togglePin(_ item: RecentWorkspaceItem) {
        item.isPinned ? store.unpin(item) : store.pin(item)
    }

    private func remove(_ item: RecentWorkspaceItem) {
        store.remove(item)
        selectFirstIfNeeded()
    }

    private func removeSelected() {
        guard let item = selectedItem else { return }
        remove(item)
    }

    private func locate(_ item: RecentWorkspaceItem) {
        appDelegate.locateRecentWorkspace(item)
        refreshAvailability()
    }

    private func confirmClearAll() {
        let alert = NSAlert()
        alert.messageText = "Remove all recent workspaces?"
        alert.informativeText = "Pinned items will also be removed. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        if #available(macOS 14.0, *) {
            alert.buttons.first?.hasDestructiveAction = true
        }

        if let window = controller.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    store.clearAll()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !visibleItems.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in
            visibleItems.firstIndex { $0.id == id }
        } ?? 0

        switch direction {
        case .up:
            selectedID = visibleItems[max(0, currentIndex - 1)].id
        case .down:
            selectedID = visibleItems[min(visibleItems.count - 1, currentIndex + 1)].id
        default:
            break
        }
    }

    private func handleEscape() {
        if !search.isEmpty {
            search = ""
        } else {
            controller.close()
        }
    }

    private func postFilterAccessibilityChange() {
        guard let window = controller.window else { return }
        NSAccessibility.post(element: window, notification: .titleChanged)
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
        let characters = event.charactersIgnoringModifiers ?? ""

        if isCommand && characters == "w" {
            controller.close()
            return nil
        }

        if isCommand && event.keyCode == 51 {
            confirmClearAll()
            return nil
        }

        if isCommand && event.keyCode == 36 {
            if let selectedItem {
                retry(selectedItem)
            }
            return nil
        }

        switch event.keyCode {
        case 36:
            openSelected()
            return nil
        case 51:
            removeSelected()
            return nil
        case 53:
            handleEscape()
            return nil
        case 123, 126:
            moveSelection(.up)
            return nil
        case 124, 125:
            moveSelection(.down)
            return nil
        default:
            if !isCommand, characters.count == 1, characters.first?.isWhitespace == false {
                searchFocused = true
            }
            return event
        }
    }
}
