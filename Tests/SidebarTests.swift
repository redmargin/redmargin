import XCTest
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

        // Wait for loading
        try await Task.sleep(nanoseconds: 200_000_000)

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

        try await Task.sleep(nanoseconds: 200_000_000)

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

        try await Task.sleep(nanoseconds: 300_000_000)

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

        try await Task.sleep(nanoseconds: 200_000_000)

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

        try await Task.sleep(nanoseconds: 200_000_000)

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

        try await Task.sleep(nanoseconds: 200_000_000)

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

    // MARK: - Helpers

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
