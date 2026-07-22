import AppKit
import Combine
import Foundation
import RedmarginCore

enum RecentWorkspaceKind: String, Codable, CaseIterable, Hashable {
    case localFile
    case localFolder
    case remoteFile
    case remoteFolder

    var isFile: Bool {
        switch self {
        case .localFile, .remoteFile: return true
        case .localFolder, .remoteFolder: return false
        }
    }

    var isRemote: Bool {
        switch self {
        case .remoteFile, .remoteFolder: return true
        case .localFile, .localFolder: return false
        }
    }
}

enum RecentWorkspaceLocation: Codable, Hashable {
    case local(URL)
    case remote(RemoteLocation)
}

struct RecentWorkspaceItem: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: RecentWorkspaceKind
    var location: RecentWorkspaceLocation
    var isPinned: Bool
    var lastOpened: Date
    var lastFailureReason: String?

    init(
        id: UUID = UUID(),
        kind: RecentWorkspaceKind,
        location: RecentWorkspaceLocation,
        isPinned: Bool = false,
        lastOpened: Date = Date(),
        lastFailureReason: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.location = location
        self.isPinned = isPinned
        self.lastOpened = lastOpened
        self.lastFailureReason = lastFailureReason
    }

    static func localFile(_ url: URL, lastOpened: Date = Date()) -> RecentWorkspaceItem {
        RecentWorkspaceItem(kind: .localFile, location: .local(url.standardizedFileURL), lastOpened: lastOpened)
    }

    static func localFolder(_ url: URL, lastOpened: Date = Date()) -> RecentWorkspaceItem {
        RecentWorkspaceItem(kind: .localFolder, location: .local(url.standardizedFileURL), lastOpened: lastOpened)
    }

    static func remoteFile(_ location: RemoteLocation, lastOpened: Date = Date()) -> RecentWorkspaceItem {
        RecentWorkspaceItem(kind: .remoteFile, location: .remote(location), lastOpened: lastOpened)
    }

    static func remoteFolder(_ location: RemoteLocation, lastOpened: Date = Date()) -> RecentWorkspaceItem {
        let folderPath = location.path.hasSuffix("/") ? location.path : location.path + "/"
        let normalized = RemoteLocation(host: location.host, path: folderPath)
        return RecentWorkspaceItem(kind: .remoteFolder, location: .remote(normalized), lastOpened: lastOpened)
    }

    var storageKey: String {
        switch location {
        case .local(let url):
            return "local:\(url.standardizedFileURL.path)"
        case .remote(let location):
            return "remote:\(location.host):\(location.path)"
        }
    }

    var displayTitle: String {
        switch location {
        case .local(let url):
            let title = url.lastPathComponent
            return title.isEmpty ? url.path : title
        case .remote(let location):
            let trimmed = location.path.hasSuffix("/") ? String(location.path.dropLast()) : location.path
            let title = URL(fileURLWithPath: trimmed).lastPathComponent
            return title.isEmpty ? location.host : title
        }
    }

    var locationText: String {
        switch location {
        case .local(let url):
            return url.deletingLastPathComponent().displayPath
        case .remote(let location):
            return "\(location.host):\(location.path)"
        }
    }

    var kindLabel: String {
        kind.isFile ? "File" : "Folder"
    }

    var tierLabel: String {
        kind.isRemote ? "Remote" : "Local"
    }

    var localURL: URL? {
        guard case .local(let url) = location else { return nil }
        return url.standardizedFileURL
    }

    var remoteLocation: RemoteLocation? {
        guard case .remote(let location) = location else { return nil }
        return location
    }

    var isLocalMissing: Bool {
        guard let url = localURL else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return true
        }
        return kind == .localFolder && !isDirectory.boolValue
    }
}

enum RecentWorkspaceTierFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case local = "Local"
    case remote = "Remote"

    var id: String { rawValue }
}

enum RecentWorkspaceKindFilter: String, CaseIterable, Identifiable {
    case all = "All Kinds"
    case files = "Files"
    case folders = "Folders"

    var id: String { rawValue }
}

final class RecentWorkspaceStore: ObservableObject {
    static let defaultsKey = "RedMargin.RecentWorkspaces"
    static let corruptKey = "RedMargin.RecentWorkspaces.Corrupt"
    static let defaultMaxUnpinnedItems = 20

    @Published private(set) var items: [RecentWorkspaceItem] = []

    private let defaults: UserDefaults
    private let maxUnpinnedItems: Int

    init(defaults: UserDefaults = .standard, maxUnpinnedItems: Int = defaultMaxUnpinnedItems) {
        self.defaults = defaults
        self.maxUnpinnedItems = maxUnpinnedItems
        self.items = Self.loadItems(from: defaults)
        migrateLegacyItemsIfNeeded()
        normalizeAndPersist()
    }

    var pinned: [RecentWorkspaceItem] {
        items.filter(\.isPinned).sorted { $0.lastOpened > $1.lastOpened }
    }

    var recent: [RecentWorkspaceItem] {
        items.filter { !$0.isPinned }.sorted { $0.lastOpened > $1.lastOpened }
    }

    var menuItems: [RecentWorkspaceItem] {
        (pinned + recent).sorted { $0.lastOpened > $1.lastOpened }
    }

    func add(_ item: RecentWorkspaceItem) {
        var next = item
        if let existingIndex = items.firstIndex(where: { $0.storageKey == item.storageKey }) {
            next.id = items[existingIndex].id
            next.isPinned = items[existingIndex].isPinned
            next.lastFailureReason = nil
            items.remove(at: existingIndex)
        }
        items.append(next)
        normalizeAndPersist()
    }

    func pin(_ item: RecentWorkspaceItem) {
        update(item) { $0.isPinned = true }
    }

    func unpin(_ item: RecentWorkspaceItem) {
        update(item) { $0.isPinned = false }
    }

    func remove(_ item: RecentWorkspaceItem) {
        items.removeAll { $0.storageKey == item.storageKey }
        persist()
    }

    func clearAll() {
        items = []
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    func clearMissingLocal() {
        items.removeAll { $0.localURL != nil && $0.isLocalMissing }
        persist()
    }

    func relocate(_ item: RecentWorkspaceItem, to url: URL) {
        update(item) {
            $0.location = .local(url.standardizedFileURL)
            $0.lastFailureReason = nil
            $0.lastOpened = Date()
        }
        normalizeAndPersist()
    }

    func markRemoteFailure(_ item: RecentWorkspaceItem, reason: String) {
        update(item) { $0.lastFailureReason = reason }
    }

    func clearRemoteFailure(_ item: RecentWorkspaceItem) {
        update(item) { $0.lastFailureReason = nil }
    }

    func filtered(
        search: String,
        tier: RecentWorkspaceTierFilter,
        kind: RecentWorkspaceKindFilter,
        pinnedOnly: Bool
    ) -> [RecentWorkspaceItem] {
        let query = PaletteSearchQuery(search)

        return (pinned + recent).filter { item in
            if pinnedOnly && !item.isPinned { return false }
            switch tier {
            case .all: break
            case .local where item.kind.isRemote: return false
            case .remote where !item.kind.isRemote: return false
            default: break
            }
            switch kind {
            case .all: break
            case .files where !item.kind.isFile: return false
            case .folders where item.kind.isFile: return false
            default: break
            }
            guard !query.isEmpty else { return true }
            return query.score(item) != nil
        }
    }

    private func update(_ item: RecentWorkspaceItem, change: (inout RecentWorkspaceItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.storageKey == item.storageKey }) else { return }
        change(&items[index])
        persist()
    }

    private func normalizeAndPersist() {
        var byKey: [String: RecentWorkspaceItem] = [:]
        for item in items {
            if let existing = byKey[item.storageKey] {
                var winner = existing.lastOpened >= item.lastOpened ? existing : item
                winner.isPinned = existing.isPinned || item.isPinned
                byKey[item.storageKey] = winner
            } else {
                byKey[item.storageKey] = item
            }
        }

        let pinnedItems = byKey.values.filter(\.isPinned).sorted { $0.lastOpened > $1.lastOpened }
        let recentItems = byKey.values
            .filter { !$0.isPinned }
            .sorted { $0.lastOpened > $1.lastOpened }
            .prefix(maxUnpinnedItems)
        items = pinnedItems + recentItems
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func loadItems(from defaults: UserDefaults) -> [RecentWorkspaceItem] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        do {
            return try JSONDecoder().decode([RecentWorkspaceItem].self, from: data)
        } catch {
            defaults.set(data, forKey: corruptKey)
            print("[RecentWorkspaceStore] corrupt JSON, recovered to .Corrupt key")
            return []
        }
    }

    private func migrateLegacyItemsIfNeeded() {
        let migrator = RecentWorkspaceMigrator(defaults: defaults)
        guard !migrator.hasCompletedMigration else { return }

        let migrated = migrator.migratedItems()
        if !migrated.isEmpty {
            items.append(contentsOf: migrated)
            normalizeAndPersist()
        }

        // Recorded even when nothing was found, so the legacy keys are read exactly
        // once. Tracking completion separately is what lets the migration keep its
        // own source: deleting the legacy keys was the only way it could otherwise
        // avoid re-importing them on the next launch.
        migrator.markMigrationCompleted()
    }
}

struct RecentWorkspaceMigrator {
    private struct LegacyRecentFolderItem: Codable {
        enum Kind: String, Codable {
            case local
            case remote
        }

        let kind: Kind
        let path: String
        let host: String?
    }

    private let defaults: UserDefaults
    private let recentFoldersKey = "RedMargin.RecentFolders"
    private let legacyRecentURLsKey = "RedMargin.RecentDocumentURLs"
    private let legacyRecentFolderURLsKey = "RedMargin.RecentFolderURLs"
    private let legacyRecentRemoteLocationsKey = "RedMargin.RecentRemoteLocations"

    /// Records that the legacy keys have been folded in. Tracking completion here
    /// means the migration never deletes its own source: the legacy keys stay
    /// readable, so an older build still finds the recents it wrote.
    static let migrationVersionKey = "RedMargin.RecentWorkspaces.LegacyMigrationVersion"
    static let currentMigrationVersion = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedMigration: Bool {
        defaults.integer(forKey: Self.migrationVersionKey) >= Self.currentMigrationVersion
    }

    func markMigrationCompleted() {
        defaults.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
    }

    func migratedItems(now: Date = Date()) -> [RecentWorkspaceItem] {
        var result: [RecentWorkspaceItem] = []
        result.append(contentsOf: migrateRecentFolders(now: now))
        result.append(contentsOf: migrateLocalPaths(forKey: legacyRecentURLsKey, kind: .localFile, now: now))
        result.append(contentsOf: migrateLocalPaths(forKey: legacyRecentFolderURLsKey, kind: .localFolder, now: now))
        result.append(contentsOf: migrateLegacyRemoteLocations(now: now))
        return result
    }

    private func migrateRecentFolders(now: Date) -> [RecentWorkspaceItem] {
        guard let data = defaults.data(forKey: recentFoldersKey),
              let legacyItems = try? JSONDecoder().decode([LegacyRecentFolderItem].self, from: data) else {
            return []
        }

        return legacyItems.enumerated().compactMap { index, item in
            let opened = now.addingTimeInterval(TimeInterval(-index))
            switch item.kind {
            case .local:
                return .localFolder(URL(fileURLWithPath: item.path).standardizedFileURL, lastOpened: opened)
            case .remote:
                guard let host = item.host else { return nil }
                return .remoteFolder(RemoteLocation(host: host, path: item.path), lastOpened: opened)
            }
        }
    }

    private func migrateLocalPaths(
        forKey key: String,
        kind: RecentWorkspaceKind,
        now: Date
    ) -> [RecentWorkspaceItem] {
        guard let paths = defaults.stringArray(forKey: key) else { return [] }
        return paths.enumerated().map { index, path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let opened = now.addingTimeInterval(TimeInterval(-index))
            return kind == .localFile ? .localFile(url, lastOpened: opened) : .localFolder(url, lastOpened: opened)
        }
    }

    private func migrateLegacyRemoteLocations(now: Date) -> [RecentWorkspaceItem] {
        guard let data = defaults.data(forKey: legacyRecentRemoteLocationsKey),
              let locations = try? JSONDecoder().decode([RemoteLocation].self, from: data) else {
            return []
        }

        return locations.enumerated().map { index, location in
            .remoteFolder(location, lastOpened: now.addingTimeInterval(TimeInterval(-index)))
        }
    }
}
