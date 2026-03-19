import Foundation
import RedmarginCore

/// Handles per-document settings persistence to UserDefaults
final class DocumentSettingsStorage {
    static let shared = DocumentSettingsStorage()

    private let scrollPositionsKey = "RedMargin.ScrollPositions"
    private let remoteScrollPositionsKey = "RedMargin.RemoteScrollPositions"
    private let lineNumbersKey = "RedMargin.DocumentLineNumbers"
    private let remoteLineNumbersKey = "RedMargin.RemoteDocumentLineNumbers"
    private let gutterKey = "RedMargin.DocumentGutter"
    private let remoteGutterKey = "RedMargin.RemoteDocumentGutter"
    private let gitIndicatorsKey = "RedMargin.DocumentGitIndicators"
    private let remoteGitIndicatorsKey = "RedMargin.RemoteDocumentGitIndicators"
    private let sidebarVisibleKey = "RedMargin.DocumentSidebarVisible"
    private let remoteSidebarVisibleKey = "RedMargin.RemoteDocumentSidebarVisible"
    private let sidebarWidthKey = "RedMargin.DocumentSidebarWidth"
    private let remoteSidebarWidthKey = "RedMargin.RemoteDocumentSidebarWidth"
    private let hiddenFilesKey = "RedMargin.DocumentHiddenFiles"
    private let remoteHiddenFilesKey = "RedMargin.RemoteDocumentHiddenFiles"
    private let expandedFoldersKey = "RedMargin.ExpandedFolders"
    private let remoteExpandedFoldersKey = "RedMargin.RemoteExpandedFolders"

    private init() {}

    // MARK: - Scroll Position

    func saveScrollPosition(_ position: Double, for url: URL) {
        var positions = UserDefaults.standard.dictionary(forKey: scrollPositionsKey) as? [String: Double] ?? [:]
        positions[url.path] = position
        UserDefaults.standard.set(positions, forKey: scrollPositionsKey)
    }

    func loadScrollPosition(for url: URL) -> Double {
        let positions = UserDefaults.standard.dictionary(forKey: scrollPositionsKey) as? [String: Double] ?? [:]
        return positions[url.path] ?? 0
    }

    func saveScrollPosition(_ position: Double, for location: RemoteLocation) {
        var positions = UserDefaults.standard.dictionary(forKey: remoteScrollPositionsKey) as? [String: Double] ?? [:]
        positions[location.storageKey] = position
        UserDefaults.standard.set(positions, forKey: remoteScrollPositionsKey)
    }

    func loadScrollPosition(for location: RemoteLocation) -> Double {
        let positions = UserDefaults.standard.dictionary(forKey: remoteScrollPositionsKey) as? [String: Double] ?? [:]
        return positions[location.storageKey] ?? 0
    }

    // MARK: - Line Numbers

    func saveLineNumbersVisible(_ visible: Bool, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: lineNumbersKey) as? [String: Bool] ?? [:]
        settings[url.path] = visible
        UserDefaults.standard.set(settings, forKey: lineNumbersKey)
    }

    func loadLineNumbersVisible(for url: URL) -> Bool {
        let settings = UserDefaults.standard.dictionary(forKey: lineNumbersKey) as? [String: Bool] ?? [:]
        return settings[url.path] ?? false
    }

    func saveLineNumbersVisible(_ visible: Bool, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteLineNumbersKey) as? [String: Bool] ?? [:]
        settings[location.storageKey] = visible
        UserDefaults.standard.set(settings, forKey: remoteLineNumbersKey)
    }

    func loadLineNumbersVisible(for location: RemoteLocation) -> Bool {
        let settings = UserDefaults.standard.dictionary(forKey: remoteLineNumbersKey) as? [String: Bool] ?? [:]
        return settings[location.storageKey] ?? false
    }

    // MARK: - Gutter

    func saveGutterVisible(_ visible: Bool, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: gutterKey) as? [String: Bool] ?? [:]
        settings[url.path] = visible
        UserDefaults.standard.set(settings, forKey: gutterKey)
    }

    func loadGutterVisible(for url: URL) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: gutterKey) as? [String: Bool] ?? [:]
        return settings[url.path]
    }

    func saveGutterVisible(_ visible: Bool, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteGutterKey) as? [String: Bool] ?? [:]
        settings[location.storageKey] = visible
        UserDefaults.standard.set(settings, forKey: remoteGutterKey)
    }

    func loadGutterVisible(for location: RemoteLocation) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: remoteGutterKey) as? [String: Bool] ?? [:]
        return settings[location.storageKey]
    }

    // MARK: - Git Indicators

    func saveGitIndicatorsVisible(_ visible: Bool, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: gitIndicatorsKey) as? [String: Bool] ?? [:]
        settings[url.path] = visible
        UserDefaults.standard.set(settings, forKey: gitIndicatorsKey)
    }

    func loadGitIndicatorsVisible(for url: URL) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: gitIndicatorsKey) as? [String: Bool] ?? [:]
        return settings[url.path]
    }

    func saveGitIndicatorsVisible(_ visible: Bool, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteGitIndicatorsKey) as? [String: Bool] ?? [:]
        settings[location.storageKey] = visible
        UserDefaults.standard.set(settings, forKey: remoteGitIndicatorsKey)
    }

    func loadGitIndicatorsVisible(for location: RemoteLocation) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: remoteGitIndicatorsKey) as? [String: Bool] ?? [:]
        return settings[location.storageKey]
    }

    // MARK: - Hidden Files

    func saveHiddenFilesVisible(_ visible: Bool, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: hiddenFilesKey) as? [String: Bool] ?? [:]
        settings[url.path] = visible
        UserDefaults.standard.set(settings, forKey: hiddenFilesKey)
    }

    func loadHiddenFilesVisible(for url: URL) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: hiddenFilesKey) as? [String: Bool] ?? [:]
        return settings[url.path]
    }

    func saveHiddenFilesVisible(_ visible: Bool, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteHiddenFilesKey) as? [String: Bool] ?? [:]
        settings[location.storageKey] = visible
        UserDefaults.standard.set(settings, forKey: remoteHiddenFilesKey)
    }

    func loadHiddenFilesVisible(for location: RemoteLocation) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: remoteHiddenFilesKey) as? [String: Bool] ?? [:]
        return settings[location.storageKey]
    }

    // MARK: - Sidebar Visible

    func saveSidebarVisible(_ visible: Bool, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: sidebarVisibleKey) as? [String: Bool] ?? [:]
        settings[url.path] = visible
        UserDefaults.standard.set(settings, forKey: sidebarVisibleKey)
    }

    func loadSidebarVisible(for url: URL) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: sidebarVisibleKey) as? [String: Bool] ?? [:]
        return settings[url.path]
    }

    func saveSidebarVisible(_ visible: Bool, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteSidebarVisibleKey) as? [String: Bool] ?? [:]
        settings[location.storageKey] = visible
        UserDefaults.standard.set(settings, forKey: remoteSidebarVisibleKey)
    }

    func loadSidebarVisible(for location: RemoteLocation) -> Bool? {
        let settings = UserDefaults.standard.dictionary(forKey: remoteSidebarVisibleKey) as? [String: Bool] ?? [:]
        return settings[location.storageKey]
    }

    // MARK: - Sidebar Width

    func saveSidebarWidth(_ width: CGFloat, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: sidebarWidthKey) as? [String: Double] ?? [:]
        settings[url.path] = Double(width)
        UserDefaults.standard.set(settings, forKey: sidebarWidthKey)
    }

    func loadSidebarWidth(for url: URL) -> CGFloat? {
        let settings = UserDefaults.standard.dictionary(forKey: sidebarWidthKey) as? [String: Double] ?? [:]
        if let width = settings[url.path] {
            return CGFloat(width)
        }
        return nil
    }

    func saveSidebarWidth(_ width: CGFloat, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteSidebarWidthKey) as? [String: Double] ?? [:]
        settings[location.storageKey] = Double(width)
        UserDefaults.standard.set(settings, forKey: remoteSidebarWidthKey)
    }

    func loadSidebarWidth(for location: RemoteLocation) -> CGFloat? {
        let settings = UserDefaults.standard.dictionary(forKey: remoteSidebarWidthKey) as? [String: Double] ?? [:]
        if let width = settings[location.storageKey] {
            return CGFloat(width)
        }
        return nil
    }

    // MARK: - Text Width

    private let textWidthKey = "RedMargin.DocumentTextWidth"
    private let remoteTextWidthKey = "RedMargin.RemoteDocumentTextWidth"

    func saveTextWidth(_ value: String, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: textWidthKey) as? [String: String] ?? [:]
        settings[url.path] = value
        UserDefaults.standard.set(settings, forKey: textWidthKey)
    }

    func loadTextWidth(for url: URL) -> String? {
        let settings = UserDefaults.standard.dictionary(forKey: textWidthKey) as? [String: String] ?? [:]
        return settings[url.path]
    }

    func saveTextWidth(_ value: String, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteTextWidthKey) as? [String: String] ?? [:]
        settings[location.storageKey] = value
        UserDefaults.standard.set(settings, forKey: remoteTextWidthKey)
    }

    func loadTextWidth(for location: RemoteLocation) -> String? {
        let settings = UserDefaults.standard.dictionary(forKey: remoteTextWidthKey) as? [String: String] ?? [:]
        return settings[location.storageKey]
    }

    // MARK: - Content Width

    private let contentWidthKey = "RedMargin.DocumentContentWidth"
    private let remoteContentWidthKey = "RedMargin.RemoteDocumentContentWidth"

    func saveContentWidth(_ value: String, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: contentWidthKey) as? [String: String] ?? [:]
        settings[url.path] = value
        UserDefaults.standard.set(settings, forKey: contentWidthKey)
    }

    func loadContentWidth(for url: URL) -> String? {
        let settings = UserDefaults.standard.dictionary(forKey: contentWidthKey) as? [String: String] ?? [:]
        return settings[url.path]
    }

    func saveContentWidth(_ value: String, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(forKey: remoteContentWidthKey) as? [String: String] ?? [:]
        settings[location.storageKey] = value
        UserDefaults.standard.set(settings, forKey: remoteContentWidthKey)
    }

    func loadContentWidth(for location: RemoteLocation) -> String? {
        let settings = UserDefaults.standard.dictionary(forKey: remoteContentWidthKey) as? [String: String] ?? [:]
        return settings[location.storageKey]
    }

    // MARK: - Expanded Folders

    func saveExpandedFolders(_ paths: Set<String>, for rootPath: String) {
        var settings = UserDefaults.standard.dictionary(forKey: expandedFoldersKey) as? [String: [String]] ?? [:]
        settings[rootPath] = Array(paths)
        UserDefaults.standard.set(settings, forKey: expandedFoldersKey)
    }

    func loadExpandedFolders(for rootPath: String) -> Set<String> {
        let settings = UserDefaults.standard.dictionary(forKey: expandedFoldersKey) as? [String: [String]] ?? [:]
        if let paths = settings[rootPath] {
            return Set(paths)
        }
        return []
    }

    func saveExpandedFolders(_ paths: Set<String>, forRemoteHost host: String, rootPath: String) {
        let key = "\(host):\(rootPath)"
        var settings = UserDefaults.standard.dictionary(forKey: remoteExpandedFoldersKey) as? [String: [String]] ?? [:]
        settings[key] = Array(paths)
        UserDefaults.standard.set(settings, forKey: remoteExpandedFoldersKey)
    }

    func loadExpandedFolders(forRemoteHost host: String, rootPath: String) -> Set<String> {
        let key = "\(host):\(rootPath)"
        let settings = UserDefaults.standard.dictionary(forKey: remoteExpandedFoldersKey) as? [String: [String]] ?? [:]
        if let paths = settings[key] {
            return Set(paths)
        }
        return []
    }
}
