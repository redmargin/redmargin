import XCTest
@testable import Redmargin

final class FolderWindowTests: XCTestCase {
    private var tempDir: URL!
    private var savedRecentWorkspaces: Data?
    private var savedCorruptRecentWorkspaces: Data?
    private var savedRecentFolderItems: Data?
    private var savedLegacyMixedRecents: [String]?
    private var savedLegacyRecentFolders: [String]?
    private var savedLegacyRecentRemoteFolders: Data?
    private var savedFolderSelectedFiles: [String: String]?

    private let recentWorkspacesKey = "RedMargin.RecentWorkspaces"
    private let corruptRecentWorkspacesKey = "RedMargin.RecentWorkspaces.Corrupt"
    private let recentFoldersKey = "RedMargin.RecentFolders"
    private let legacyMixedRecentsKey = "RedMargin.RecentDocumentURLs"
    private let legacyRecentFoldersKey = "RedMargin.RecentFolderURLs"
    private let legacyRecentRemoteFoldersKey = "RedMargin.RecentRemoteLocations"
    private let folderSelectedFilesKey = "RedMargin.FolderSelectedFiles"

    override func setUp() async throws {
        savedRecentWorkspaces = UserDefaults.standard.data(forKey: recentWorkspacesKey)
        savedCorruptRecentWorkspaces = UserDefaults.standard.data(forKey: corruptRecentWorkspacesKey)
        savedRecentFolderItems = UserDefaults.standard.data(forKey: recentFoldersKey)
        savedLegacyMixedRecents = UserDefaults.standard.stringArray(forKey: legacyMixedRecentsKey)
        savedLegacyRecentFolders = UserDefaults.standard.stringArray(forKey: legacyRecentFoldersKey)
        savedLegacyRecentRemoteFolders = UserDefaults.standard.data(forKey: legacyRecentRemoteFoldersKey)
        savedFolderSelectedFiles = UserDefaults.standard.dictionary(forKey: folderSelectedFilesKey) as? [String: String]
        UserDefaults.standard.removeObject(forKey: recentWorkspacesKey)
        UserDefaults.standard.removeObject(forKey: corruptRecentWorkspacesKey)
        UserDefaults.standard.removeObject(forKey: legacyMixedRecentsKey)
        UserDefaults.standard.removeObject(forKey: recentFoldersKey)
        UserDefaults.standard.removeObject(forKey: legacyRecentFoldersKey)
        UserDefaults.standard.removeObject(forKey: legacyRecentRemoteFoldersKey)
        UserDefaults.standard.removeObject(forKey: folderSelectedFilesKey)

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderWindowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        restoreUserDefaults(savedRecentWorkspaces, forKey: recentWorkspacesKey)
        restoreUserDefaults(savedCorruptRecentWorkspaces, forKey: corruptRecentWorkspacesKey)
        restoreUserDefaults(savedRecentFolderItems, forKey: recentFoldersKey)
        restoreUserDefaults(savedLegacyMixedRecents, forKey: legacyMixedRecentsKey)
        restoreUserDefaults(savedLegacyRecentFolders, forKey: legacyRecentFoldersKey)
        restoreUserDefaults(savedLegacyRecentRemoteFolders, forKey: legacyRecentRemoteFoldersKey)
        restoreUserDefaults(savedFolderSelectedFiles, forKey: folderSelectedFilesKey)
    }

    private func restoreUserDefaults(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor
    func testOpenFolderCreatesWindow() throws {
        let appDelegate = AppDelegate()

        appDelegate.openFolder(tempDir)

        let standardized = tempDir.standardizedFileURL
        let window = appDelegate.folderWindows[standardized]
        XCTAssertNotNil(window, "openFolder should create a window tracked in folderWindows")
        XCTAssertEqual(appDelegate.recentWorkspaces.items.first?.kind, .localFolder)
        XCTAssertEqual(appDelegate.recentWorkspaces.items.first?.localURL, standardized)

        window?.close()
    }

    @MainActor
    func testOpeningLocalFileRecordsRecentWorkspace() throws {
        let appDelegate = AppDelegate()
        let file = tempDir.appendingPathComponent("document.md")
        try "# Document".write(to: file, atomically: true, encoding: .utf8)

        appDelegate.openDocument(file)

        XCTAssertEqual(appDelegate.recentWorkspaces.items.first?.kind, .localFile)
        XCTAssertEqual(appDelegate.recentWorkspaces.items.first?.localURL, file.standardizedFileURL)
    }

    @MainActor
    func testOpenFolderDeduplication() throws {
        let appDelegate = AppDelegate()

        appDelegate.openFolder(tempDir)
        let standardized = tempDir.standardizedFileURL
        let firstWindow = appDelegate.folderWindows[standardized]
        XCTAssertNotNil(firstWindow)

        appDelegate.openFolder(tempDir)
        let secondWindow = appDelegate.folderWindows[standardized]

        XCTAssertTrue(firstWindow === secondWindow, "Opening the same folder twice should reuse the existing window")
        XCTAssertEqual(appDelegate.folderWindows.count, 1, "Should only have one folder window")

        firstWindow?.close()
    }

    @MainActor
    func testFolderDetectionInOpenURLs() throws {
        let appDelegate = AppDelegate()

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue, "tempDir should be detected as a directory")

        appDelegate.openFolder(tempDir)

        let standardized = tempDir.standardizedFileURL
        XCTAssertNotNil(
            appDelegate.folderWindows[standardized],
            "Directory URL should be routed to openFolder"
        )
        XCTAssertTrue(
            appDelegate.remoteDocumentWindows.isEmpty,
            "Directory should not create a document window"
        )

        appDelegate.folderWindows[standardized]?.close()
    }

    @MainActor
    func testLegacyDocumentRecentsMigrateToWorkspaceFilesAndClearLegacyKey() throws {
        let standaloneFile = tempDir.appendingPathComponent("standalone.md")
        try "# Standalone".write(to: standaloneFile, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(
            [standaloneFile.path],
            forKey: legacyMixedRecentsKey
        )

        let appDelegate = AppDelegate()

        XCTAssertEqual(appDelegate.recentWorkspaces.items.first?.kind, .localFile)
        XCTAssertEqual(appDelegate.recentWorkspaces.items.first?.localURL, standaloneFile.standardizedFileURL)
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyMixedRecentsKey))
    }

    @MainActor
    func testRecentFoldersHaveRetention() throws {
        let appDelegate = AppDelegate()

        for index in 0..<25 {
            let folder = tempDir.appendingPathComponent("folder-\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            appDelegate.recentWorkspaces.add(.localFolder(folder))
        }

        XCTAssertEqual(appDelegate.recentWorkspaces.recent.count, appDelegate.maxRecentItems)
        XCTAssertEqual(appDelegate.recentWorkspaces.recent.first?.localURL?.lastPathComponent, "folder-24")
    }

    @MainActor
    func testRemoteFolderMovesAheadOfLocalFolders() throws {
        let appDelegate = AppDelegate()
        let remoteFolder = RemoteLocation(host: "cognel-dev", path: "/work/docs/")

        appDelegate.recentWorkspaces.add(.localFolder(tempDir))
        appDelegate.recentWorkspaces.add(.remoteFolder(remoteFolder))

        XCTAssertEqual(appDelegate.recentWorkspaces.recent.first?.remoteLocation, remoteFolder)
        XCTAssertEqual(appDelegate.recentWorkspaces.recent.dropFirst().first?.localURL, tempDir.standardizedFileURL)
    }

    @MainActor
    func testRecentFolderRemembersLastSelectedFile() throws {
        let appDelegate = AppDelegate()
        let selectedFile = tempDir.appendingPathComponent("selected.md")
        try "# Selected".write(to: selectedFile, atomically: true, encoding: .utf8)

        appDelegate.updateFolderWindowFile(folder: tempDir, to: selectedFile)

        let reloadedAppDelegate = AppDelegate()
        XCTAssertEqual(
            reloadedAppDelegate.savedSelectedFile(for: tempDir),
            selectedFile.standardizedFileURL
        )
    }

    @MainActor
    func testRecentFolderOpensWhenSavedSelectedFileIsMissing() throws {
        let appDelegate = AppDelegate()
        let selectedFile = tempDir.appendingPathComponent("missing.md")

        appDelegate.updateFolderWindowFile(folder: tempDir, to: selectedFile)
        appDelegate.openFolder(tempDir, selectedFile: appDelegate.savedSelectedFile(for: tempDir))

        XCTAssertNil(appDelegate.savedSelectedFile(for: tempDir))
        XCTAssertNotNil(appDelegate.folderWindows[tempDir.standardizedFileURL])
    }
}
