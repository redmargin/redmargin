import XCTest
import WebKit
@testable import Redmargin
@testable import RedmarginLib
@testable import RedmarginCore

/// Wraps the real `LocalFileProvider` and delays reads of chosen paths. The file
/// system is real; only the latency is controlled, so an earlier read can be made
/// to finish after a later one and the last-response-wins races become
/// reproducible instead of timing-dependent.
private final class DelayingFileProvider: FileProvider, @unchecked Sendable {
    private let wrapped = LocalFileProvider()
    private let readDelays: [String: TimeInterval]

    init(readDelays: [String: TimeInterval]) {
        self.readDelays = readDelays
    }

    func readFile(at path: String) async throws -> String {
        if let delay = readDelays[path] {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try await wrapped.readFile(at: path)
    }

    func writeFile(at path: String, content: String) async throws {
        try await wrapped.writeFile(at: path, content: content)
    }

    func watchFile(at path: String, onChange: @escaping () -> Void) async -> WatchToken {
        await wrapped.watchFile(at: path, onChange: onChange)
    }

    func unwatch(_ token: WatchToken) async {
        await wrapped.unwatch(token)
    }

    func detectGitRepo(for path: String) async throws -> String? {
        try await wrapped.detectGitRepo(for: path)
    }

    func gitDiff(for path: String, repoRoot: String) async throws -> GitChangeResult {
        try await wrapped.gitDiff(for: path, repoRoot: repoRoot)
    }

    func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken {
        await wrapped.watchGitRepo(at: repoRoot, onChange: onChange)
    }
}

/// A result that arrives after the user has moved on must not be applied.
@MainActor
final class StaleResultTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StaleResultTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func write(_ contents: String, to name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - DocumentState.loadFile

    /// Selecting a second file while the first is still loading must leave the
    /// second on screen. The slow read finishes last and would otherwise replace
    /// the newest document and restore the abandoned selection.
    func testSlowLoadDoesNotReplaceNewerDocument() async throws {
        let slow = try write("# Slow\n", to: "slow.md")
        let fast = try write("# Fast\n", to: "fast.md")
        let start = try write("# Start\n", to: "start.md")

        let provider = DelayingFileProvider(readDelays: [slow.path: 0.6])
        let state = DocumentState(content: "# Start\n", fileURL: start, fileProvider: provider)

        let slowLoad = Task { try await state.loadFile(at: slow) }
        try await Task.sleep(nanoseconds: 100_000_000)
        try await state.loadFile(at: fast)

        XCTAssertEqual(state.fileURL, fast)
        XCTAssertEqual(state.content, "# Fast\n")

        _ = await slowLoad.result

        XCTAssertEqual(state.fileURL, fast, "A superseded load replaced the newer document")
        XCTAssertEqual(state.content, "# Fast\n", "A superseded load replaced the newer content")
    }

    // MARK: - DocumentState.handleCheckboxToggle

    /// The toggle belongs to the document it was clicked in. The read suspends, and
    /// if the write resolves `fileURL` again afterwards it sends the old document's
    /// content into whichever file the user navigated to.
    func testCheckboxToggleWritesToTheDocumentItWasClickedIn() async throws {
        let toggled = try write("- [ ] alpha\n", to: "toggled.md")
        let navigatedTo = try write("beta\n", to: "other.md")

        let provider = DelayingFileProvider(readDelays: [toggled.path: 0.6])
        let state = DocumentState(content: "- [ ] alpha\n", fileURL: toggled, fileProvider: provider)

        state.handleCheckboxToggle(line: 1, checked: true)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Navigate away while the toggle's read is still in flight.
        try await state.loadFile(at: navigatedTo)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(
            try read(navigatedTo),
            "beta\n",
            "The toggle wrote the previous document's content into the newly selected file"
        )
        XCTAssertEqual(try read(toggled), "- [x] alpha\n", "The toggle did not reach the file it was clicked in")
        XCTAssertEqual(state.content, "beta\n", "The toggle's content overwrote the newly selected document")
    }

    // MARK: - FindController

    private func makeLoadedWebView() async throws -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString("<html><body><p>needle needle needle</p></body></html>", baseURL: nil)

        let deadline = Date().addingTimeInterval(5)
        while webView.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try XCTSkipIf(webView.isLoading, "WebView did not finish loading")
        return webView
    }

    /// The match count is computed in the web view and delivered asynchronously.
    /// A count for a query the user has already cleared must not repopulate the UI.
    func testClearedSearchIgnoresAnInFlightCount() async throws {
        let webView = try await makeLoadedWebView()
        let controller = FindController()
        controller.webView = webView

        controller.find("needle")
        controller.clearFind()

        // Let the count callback for "needle" land.
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(controller.matchCount, 0, "A cleared search was repopulated by an older count")
        XCTAssertEqual(controller.currentMatch, 0)
        XCTAssertEqual(controller.searchText, "")
    }
}
