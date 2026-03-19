import XCTest
import AppKit
@testable import Redmargin
@testable import RedmarginLib
@testable import RedmarginCore

final class SidebarTests: XCTestCase {

    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidebarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - FileTreeProvider Tests

    func testFileTreeProviderFindsMarkdownFiles() async throws {
        // Create test files
        try "# Test 1".write(to: tempDir.appendingPathComponent("file1.md"), atomically: true, encoding: .utf8)
        try "# Test 2".write(to: tempDir.appendingPathComponent("file2.markdown"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(currentFileURL: tempDir.appendingPathComponent("file1.md"))
        try await waitForProvider(provider)

        let rootNodes = await provider.rootNodes
        let fileNames = rootNodes.map { $0.name }.sorted()

        XCTAssertEqual(fileNames, ["file1.md", "file2.markdown"])
    }

    func testFileTreeProviderIgnoresNonMarkdown() async throws {
        // Create mixed files
        try "# Markdown".write(to: tempDir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "Plain text".write(to: tempDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "Swift code".write(to: tempDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(currentFileURL: tempDir.appendingPathComponent("readme.md"))
        try await waitForProvider(provider)

        let rootNodes = await provider.rootNodes
        let fileNames = rootNodes.map { $0.name }

        XCTAssertEqual(fileNames, ["readme.md"])
        XCTAssertFalse(fileNames.contains("notes.txt"))
        XCTAssertFalse(fileNames.contains("main.swift"))
    }

    func testFileTreeProviderUsesRepoRoot() async throws {
        // Create a git repo structure
        let repoDir = tempDir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)

        // Initialize git repo
        let gitInit = try await ProcessRunner.run(
            executable: "git",
            arguments: ["init"],
            workingDirectory: repoDir
        )
        guard gitInit.exitCode == 0 else {
            throw XCTSkip("Could not initialize git repo")
        }

        // Create files at repo root and in subdirectory
        try "# Root".write(to: repoDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let subDir = repoDir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "# Doc".write(to: subDir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)

        // Create provider from file in subdirectory
        let provider = await FileTreeProvider(currentFileURL: subDir.appendingPathComponent("guide.md"))
        try await waitForProvider(provider)

        let rootDirectory = await provider.rootDirectory

        // Should use repo root, not subdirectory
        // Standardize paths to handle /var vs /private/var symlink
        XCTAssertEqual(
            rootDirectory?.standardizedFileURL.path,
            repoDir.standardizedFileURL.path
        )
    }

    func testFileTreeProviderFallsBackToDirectory() async throws {
        // Create file outside any git repo
        try "# Test".write(to: tempDir.appendingPathComponent("test.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(currentFileURL: tempDir.appendingPathComponent("test.md"))
        try await waitForProvider(provider)

        let rootDirectory = await provider.rootDirectory

        // Should use file's parent directory
        XCTAssertEqual(rootDirectory?.path, tempDir.path)
    }

    func testFileTreeProviderIgnoresHiddenDirectories() async throws {
        // Create .git directory with markdown (should be ignored)
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "# Hidden".write(to: gitDir.appendingPathComponent("hidden.md"), atomically: true, encoding: .utf8)

        // Create node_modules (should be ignored)
        let nodeDir = tempDir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        try "# Node".write(to: nodeDir.appendingPathComponent("package.md"), atomically: true, encoding: .utf8)

        // Create regular file
        try "# Visible".write(to: tempDir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(currentFileURL: tempDir.appendingPathComponent("visible.md"))
        try await waitForProvider(provider)

        let rootNodes = await provider.rootNodes
        let allNames = collectAllNames(rootNodes)

        XCTAssertTrue(allNames.contains("visible.md"))
        XCTAssertFalse(allNames.contains("hidden.md"))
        XCTAssertFalse(allNames.contains("package.md"))
        XCTAssertFalse(allNames.contains(".git"))
        XCTAssertFalse(allNames.contains("node_modules"))
    }

    func testFileTreeProviderNestedDirectories() async throws {
        // Create nested structure
        let docsDir = tempDir.appendingPathComponent("docs")
        let apiDir = docsDir.appendingPathComponent("api")
        try FileManager.default.createDirectory(at: apiDir, withIntermediateDirectories: true)

        try "# Root".write(to: tempDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "# Docs".write(to: docsDir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)
        try "# API".write(to: apiDir.appendingPathComponent("reference.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(currentFileURL: tempDir.appendingPathComponent("README.md"))
        try await waitForProvider(provider)

        let rootNodes = await provider.rootNodes
        let allNames = collectAllNames(rootNodes)

        XCTAssertTrue(allNames.contains("README.md"))
        XCTAssertTrue(allNames.contains("docs"))
        XCTAssertTrue(allNames.contains("guide.md"))
        XCTAssertTrue(allNames.contains("api"))
        XCTAssertTrue(allNames.contains("reference.md"))
    }

    // MARK: - Directory Initializer Tests

    func testDirectoryInitializer() async throws {
        // Create test files
        try "# Test 1".write(to: tempDir.appendingPathComponent("file1.md"), atomically: true, encoding: .utf8)
        try "# Test 2".write(to: tempDir.appendingPathComponent("file2.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        try await waitForDirectoryProvider(provider)

        let rootDirectory = await provider.rootDirectory
        let rootNodes = await provider.rootNodes
        let fileNames = rootNodes.map { $0.name }.sorted()

        // Should use the provided directory directly (no git detection)
        XCTAssertEqual(
            rootDirectory?.standardizedFileURL.path,
            tempDir.standardizedFileURL.path
        )
        XCTAssertEqual(fileNames, ["file1.md", "file2.md"])
    }

    func testDirectoryInitializerExcludesIgnored() async throws {
        // Create ignored directories with markdown files
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "# Hidden".write(to: gitDir.appendingPathComponent("hidden.md"), atomically: true, encoding: .utf8)

        let nodeDir = tempDir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        try "# Node".write(to: nodeDir.appendingPathComponent("package.md"), atomically: true, encoding: .utf8)

        let buildDir = tempDir.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try "# Build".write(to: buildDir.appendingPathComponent("build.md"), atomically: true, encoding: .utf8)

        // Create visible file
        try "# Visible".write(to: tempDir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        try await waitForDirectoryProvider(provider)

        let rootNodes = await provider.rootNodes
        let allNames = collectAllNames(rootNodes)

        XCTAssertTrue(allNames.contains("visible.md"))
        XCTAssertFalse(allNames.contains("hidden.md"))
        XCTAssertFalse(allNames.contains("package.md"))
        XCTAssertFalse(allNames.contains("build.md"))
        XCTAssertFalse(allNames.contains(".git"))
        XCTAssertFalse(allNames.contains("node_modules"))
        XCTAssertFalse(allNames.contains(".build"))
    }

    func testDirectoryInitializerOnlyMarkdown() async throws {
        // Create mixed file types
        try "# Markdown".write(to: tempDir.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try "# Also MD".write(to: tempDir.appendingPathComponent("notes.markdown"), atomically: true, encoding: .utf8)
        try "Plain text".write(to: tempDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "Swift code".write(to: tempDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "{}".write(to: tempDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        try await waitForDirectoryProvider(provider)

        let rootNodes = await provider.rootNodes
        let fileNames = rootNodes.map { $0.name }.sorted()

        XCTAssertEqual(fileNames, ["notes.markdown", "readme.md"])
    }

    // MARK: - FileTreeNode Tests

    func testFileTreeNodeExpansionCallback() async throws {
        var callbackPath: String?
        var callbackExpanded: Bool?

        let node = FileTreeNode(
            name: "folder",
            url: tempDir,
            isDirectory: true,
            depth: 0,
            children: [],
            isExpanded: false
        )

        node.onExpandedChange = { path, expanded in
            callbackPath = path
            callbackExpanded = expanded
        }

        node.isExpanded = true

        XCTAssertEqual(callbackPath, tempDir.path)
        XCTAssertEqual(callbackExpanded, true)
    }

    func testFileTreeNodeDefaultExpansion() {
        // Root level (depth 0) should be expanded by default
        let rootNode = FileTreeNode(
            name: "root",
            url: tempDir,
            isDirectory: true,
            depth: 0
        )
        XCTAssertTrue(rootNode.isExpanded)

        // Non-root (depth > 0) should be collapsed by default
        let childNode = FileTreeNode(
            name: "child",
            url: tempDir.appendingPathComponent("child"),
            isDirectory: true,
            depth: 1
        )
        XCTAssertFalse(childNode.isExpanded)
    }

    // MARK: - Folder Settings Persistence Tests

    func testFolderSidebarWidthPersistence() {
        let key = "RedMargin.DocumentSidebarWidth"
        let folderPath = tempDir!.path

        // No saved width initially
        let initial = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        XCTAssertNil(initial[folderPath])

        // Save width
        var settings: [String: Double] = [folderPath: 275.0]
        UserDefaults.standard.set(settings, forKey: key)

        // Load it back
        let loaded = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        XCTAssertEqual(loaded[folderPath], 275.0)

        // Update width
        settings[folderPath] = 350.0
        UserDefaults.standard.set(settings, forKey: key)
        let updated = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        XCTAssertEqual(updated[folderPath], 350.0)

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testFolderSidebarVisibilityPersistence() {
        let key = "RedMargin.DocumentSidebarVisible"
        let folderPath = tempDir!.path

        // No saved visibility initially
        let initial = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:]
        XCTAssertNil(initial[folderPath])

        // Save hidden state
        var settings: [String: Bool] = [folderPath: false]
        UserDefaults.standard.set(settings, forKey: key)
        let hidden = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:]
        XCTAssertEqual(hidden[folderPath], false)

        // Save visible state
        settings[folderPath] = true
        UserDefaults.standard.set(settings, forKey: key)
        let visible = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:]
        XCTAssertEqual(visible[folderPath], true)

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testFolderSelectedFilePersistence() {
        let key = "RedMargin.FolderSelectedFiles"
        let folderPath = tempDir!.path
        let filePath = tempDir!.appendingPathComponent("readme.md").path

        // Save selected file mapping
        let savedDict: [String: String] = [folderPath: filePath]
        UserDefaults.standard.set(savedDict, forKey: key)

        // Load it back
        let loaded = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        XCTAssertEqual(loaded[folderPath], filePath)

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testMultipleFolderSettingsIndependent() {
        let widthKey = "RedMargin.DocumentSidebarWidth"
        let visibleKey = "RedMargin.DocumentSidebarVisible"
        let selectedKey = "RedMargin.FolderSelectedFiles"

        let folder1 = tempDir!.path
        let folder2 = tempDir!.appendingPathComponent("subfolder").path

        // Save different settings for each folder
        UserDefaults.standard.set([folder1: 200.0, folder2: 350.0], forKey: widthKey)
        UserDefaults.standard.set([folder1: true, folder2: false], forKey: visibleKey)
        UserDefaults.standard.set([
            folder1: "\(folder1)/readme.md",
            folder2: "\(folder2)/notes.md"
        ], forKey: selectedKey)

        // Verify each folder's settings are independent
        let widths = UserDefaults.standard.dictionary(forKey: widthKey) as? [String: Double] ?? [:]
        XCTAssertEqual(widths[folder1], 200.0)
        XCTAssertEqual(widths[folder2], 350.0)

        let visible = UserDefaults.standard.dictionary(forKey: visibleKey) as? [String: Bool] ?? [:]
        XCTAssertEqual(visible[folder1], true)
        XCTAssertEqual(visible[folder2], false)

        let selected = UserDefaults.standard.dictionary(forKey: selectedKey) as? [String: String] ?? [:]
        XCTAssertEqual(selected[folder1], "\(folder1)/readme.md")
        XCTAssertEqual(selected[folder2], "\(folder2)/notes.md")

        // Clean up
        UserDefaults.standard.removeObject(forKey: widthKey)
        UserDefaults.standard.removeObject(forKey: visibleKey)
        UserDefaults.standard.removeObject(forKey: selectedKey)
    }

    // MARK: - Folder Window Integration Tests

    @MainActor
    func testOpenFolderCreatesWindow() throws {
        let appDelegate = AppDelegate()

        appDelegate.openFolder(tempDir)

        let standardized = tempDir.standardizedFileURL
        let window = appDelegate.folderWindows[standardized]
        XCTAssertNotNil(window, "openFolder should create a window tracked in folderWindows")

        // Clean up
        window?.close()
    }

    @MainActor
    func testOpenFolderDeduplication() throws {
        let appDelegate = AppDelegate()

        appDelegate.openFolder(tempDir)
        let standardized = tempDir.standardizedFileURL
        let firstWindow = appDelegate.folderWindows[standardized]
        XCTAssertNotNil(firstWindow)

        // Open same folder again
        appDelegate.openFolder(tempDir)
        let secondWindow = appDelegate.folderWindows[standardized]

        XCTAssertTrue(firstWindow === secondWindow, "Opening the same folder twice should reuse the existing window")
        XCTAssertEqual(appDelegate.folderWindows.count, 1, "Should only have one folder window")

        // Clean up
        firstWindow?.close()
    }

    @MainActor
    func testFolderDetectionInOpenURLs() throws {
        let appDelegate = AppDelegate()

        // Verify directory detection routes to openFolder (not openDocument)
        // This replicates the logic in application(_:open:)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue, "tempDir should be detected as a directory")

        // Route to openFolder as application(_:open:) would
        appDelegate.openFolder(tempDir)

        let standardized = tempDir.standardizedFileURL
        XCTAssertNotNil(
            appDelegate.folderWindows[standardized],
            "Directory URL should be routed to openFolder"
        )
        // Verify it's NOT tracked as a document window
        XCTAssertTrue(
            appDelegate.remoteDocumentWindows.isEmpty,
            "Directory should not create a document window"
        )

        // Clean up
        appDelegate.folderWindows[standardized]?.close()
    }

    // MARK: - Hidden Files Tests

    func testHiddenFilesExcludedByDefault() async throws {
        try "# Hidden".write(to: tempDir.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try "# Visible".write(to: tempDir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        try await waitForDirectoryProvider(provider)

        let allNames = collectAllNames(await provider.rootNodes)
        XCTAssertTrue(allNames.contains("visible.md"))
        XCTAssertFalse(allNames.contains(".hidden.md"))
    }

    func testHiddenFilesIncludedWhenEnabled() async throws {
        try "# Hidden".write(to: tempDir.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try "# Visible".write(to: tempDir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        await MainActor.run { provider.showHiddenFiles = true }
        try await waitForDirectoryProvider(provider)

        let allNames = collectAllNames(await provider.rootNodes)
        XCTAssertTrue(allNames.contains("visible.md"))
        XCTAssertTrue(allNames.contains(".hidden.md"))
    }

    func testHiddenFoldersExcludedByDefault() async throws {
        let hiddenDir = tempDir.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try "# In Hidden".write(to: hiddenDir.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let visibleDir = tempDir.appendingPathComponent("visible")
        try FileManager.default.createDirectory(at: visibleDir, withIntermediateDirectories: true)
        try "# In Visible".write(to: visibleDir.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        try await waitForDirectoryProvider(provider)

        let allNames = collectAllNames(await provider.rootNodes)
        XCTAssertTrue(allNames.contains("visible"))
        XCTAssertFalse(allNames.contains(".hidden"))
    }

    func testHiddenFoldersIncludedWhenEnabled() async throws {
        let hiddenDir = tempDir.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try "# In Hidden".write(to: hiddenDir.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let visibleDir = tempDir.appendingPathComponent("visible")
        try FileManager.default.createDirectory(at: visibleDir, withIntermediateDirectories: true)
        try "# In Visible".write(to: visibleDir.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        await MainActor.run { provider.showHiddenFiles = true }
        try await waitForDirectoryProvider(provider)

        let allNames = collectAllNames(await provider.rootNodes)
        XCTAssertTrue(allNames.contains("visible"))
        XCTAssertTrue(allNames.contains(".hidden"))
    }

    func testGitDirectoryAlwaysExcluded() async throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "# Git".write(to: gitDir.appendingPathComponent("config.md"), atomically: true, encoding: .utf8)

        try "# Visible".write(to: tempDir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        await MainActor.run { provider.showHiddenFiles = true }
        try await waitForDirectoryProvider(provider)

        let allNames = collectAllNames(await provider.rootNodes)
        XCTAssertTrue(allNames.contains("visible.md"))
        XCTAssertFalse(allNames.contains(".git"))
        XCTAssertFalse(allNames.contains("config.md"))
    }

    func testIgnoredDirectoriesStillExcludedWhenShowingHidden() async throws {
        let nodeDir = tempDir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        try "# Node".write(to: nodeDir.appendingPathComponent("pkg.md"), atomically: true, encoding: .utf8)

        let buildDir = tempDir.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try "# Build".write(to: buildDir.appendingPathComponent("out.md"), atomically: true, encoding: .utf8)

        try "# Visible".write(to: tempDir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)

        let provider = await FileTreeProvider(rootDirectory: tempDir)
        await MainActor.run { provider.showHiddenFiles = true }
        try await waitForDirectoryProvider(provider)

        let allNames = collectAllNames(await provider.rootNodes)
        XCTAssertTrue(allNames.contains("visible.md"))
        XCTAssertFalse(allNames.contains("node_modules"))
        XCTAssertFalse(allNames.contains(".build"))
    }

    // MARK: - Helpers

    /// Waits for a directory-initialized FileTreeProvider to finish building its tree.
    private func waitForDirectoryProvider(_ provider: FileTreeProvider, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        try await Task.sleep(nanoseconds: 100_000_000)
        while await provider.rootNodes.isEmpty {
            if Date() > deadline {
                XCTFail("FileTreeProvider tree build timed out after \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Waits for a FileTreeProvider to finish its async loading, with a timeout.
    private func waitForProvider(_ provider: FileTreeProvider, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        // Wait for loading to start
        try await Task.sleep(nanoseconds: 50_000_000)
        // Then wait for it to finish
        while await provider.isLoading {
            if Date() > deadline {
                XCTFail("FileTreeProvider loading timed out after \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func collectAllNames(_ nodes: [FileTreeNode]) -> Set<String> {
        var names = Set<String>()
        for node in nodes {
            names.insert(node.name)
            if !node.children.isEmpty {
                names.formUnion(collectAllNames(node.children))
            }
        }
        return names
    }
}
