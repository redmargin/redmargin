import XCTest
import WebKit
@testable import RedmarginLib

final class FindTests: XCTestCase {
    private var webView: WKWebView!
    private var navigationDelegate: TestNavigationDelegate!
    private var findController: FindController!

    /// Get WebRenderer directory from project source (works during tests)
    private var webRendererURL: URL {
        let testFilePath = URL(fileURLWithPath: #file)
        let projectRoot = testFilePath
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // redmargin/
        return projectRoot.appendingPathComponent("WebRenderer")
    }

    override func setUp() {
        super.setUp()

        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        navigationDelegate = TestNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
        findController = FindController()
        findController.webView = webView
    }

    override func tearDown() {
        webView = nil
        navigationDelegate = nil
        findController = nil
        super.tearDown()
    }

    private func loadRendererAndRender(_ markdown: String) {
        let loadExpectation = XCTestExpectation(description: "WebView loads")

        let rendererURL = webRendererURL
            .appendingPathComponent("src")
            .appendingPathComponent("renderer.html")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: rendererURL.path),
            "renderer.html should exist at \(rendererURL.path)"
        )

        navigationDelegate.onFinish = {
            loadExpectation.fulfill()
        }

        navigationDelegate.onError = { error in
            XCTFail("Navigation failed: \(error)")
            loadExpectation.fulfill()
        }

        let accessURL = URL(fileURLWithPath: "/")
        webView.loadFileURL(rendererURL, allowingReadAccessTo: accessURL)

        wait(for: [loadExpectation], timeout: 10.0)

        // Render markdown
        let renderExpectation = XCTestExpectation(description: "Render completes")

        let payload: [String: Any] = [
            "markdown": markdown,
            "options": [
                "theme": "light",
                "basePath": ""
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            XCTFail("Failed to serialize JSON")
            return
        }

        let escapedJSON = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = "window.App.render(JSON.parse('\(escapedJSON)'))"

        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                XCTFail("Render error: \(error)")
            }
            renderExpectation.fulfill()
        }

        wait(for: [renderExpectation], timeout: 5.0)
    }

    func testFindHighlightsMatches() {
        loadRendererAndRender("test one test two test three")

        let findExpectation = XCTestExpectation(description: "Find completes")

        findController.find("test")

        // Wait for async JavaScript execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            findExpectation.fulfill()
        }

        wait(for: [findExpectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 3, "Should find 3 matches of 'test'")
        XCTAssertEqual(findController.currentMatch, 1, "Should be on first match")
    }

    func testFindNoMatches() {
        loadRendererAndRender("hello world")

        let findExpectation = XCTestExpectation(description: "Find completes")

        findController.find("xyz")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            findExpectation.fulfill()
        }

        wait(for: [findExpectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 0, "Should find 0 matches")
        XCTAssertEqual(findController.currentMatch, 0, "Current match should be 0")
    }

    func testFindNextCyclesToFirst() {
        loadRendererAndRender("apple banana apple cherry apple")

        let findExpectation = XCTestExpectation(description: "Find completes")

        findController.find("apple")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            findExpectation.fulfill()
        }

        wait(for: [findExpectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 3, "Should find 3 matches")
        XCTAssertEqual(findController.currentMatch, 1, "Should start at match 1")

        findController.findNext()
        XCTAssertEqual(findController.currentMatch, 2, "Should be at match 2")

        findController.findNext()
        XCTAssertEqual(findController.currentMatch, 3, "Should be at match 3")

        findController.findNext()
        XCTAssertEqual(findController.currentMatch, 1, "Should cycle to match 1")
    }

    func testFindPreviousFromFirst() {
        loadRendererAndRender("apple banana apple cherry apple")

        let findExpectation = XCTestExpectation(description: "Find completes")

        findController.find("apple")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            findExpectation.fulfill()
        }

        wait(for: [findExpectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 3, "Should find 3 matches")
        XCTAssertEqual(findController.currentMatch, 1, "Should start at match 1")

        findController.findPrevious()
        XCTAssertEqual(findController.currentMatch, 3, "Should cycle to match 3")
    }

    func testClearFindRemovesHighlights() {
        loadRendererAndRender("test one test two")

        let findExpectation = XCTestExpectation(description: "Find completes")

        findController.find("test")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            findExpectation.fulfill()
        }

        wait(for: [findExpectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 2, "Should find 2 matches")

        findController.clearFind()

        XCTAssertEqual(findController.matchCount, 0, "Match count should be 0 after clear")
        XCTAssertEqual(findController.currentMatch, 0, "Current match should be 0 after clear")
        XCTAssertEqual(findController.searchText, "", "Search text should be empty after clear")
    }

    // MARK: - Regression tests

    /// Regression: searchText binding must trigger find() to produce matches.
    /// FolderWindowContent was missing the onChange handler so typing in the
    /// FindBar updated searchText but never called find(), leaving matchCount at 0.
    func testSearchTextUpdateWithoutFindProducesNoMatches() {
        loadRendererAndRender("hello world hello")

        // Simulate what happens when only the binding updates searchText
        // but find() is never called (the bug in FolderWindowContent)
        findController.searchText = "hello"

        let expectation = XCTestExpectation(description: "Wait for potential async")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        // Without calling find(), matchCount stays at 0 — this IS the bug
        XCTAssertEqual(findController.matchCount, 0,
                       "Setting searchText without calling find() must not produce matches")
        XCTAssertEqual(findController.currentMatch, 0,
                       "Setting searchText without calling find() must not advance currentMatch")
    }

    /// Regression: calling find() after setting searchText must produce results.
    /// This is the correct flow when the onChange handler is wired up.
    func testSearchTextUpdateThenFindProducesMatches() {
        loadRendererAndRender("hello world hello")

        // Simulate the correct flow: binding updates searchText, onChange calls find()
        findController.searchText = "hello"
        findController.find("hello")

        let expectation = XCTestExpectation(description: "Find completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 2, "Should find 2 matches of 'hello'")
        XCTAssertEqual(findController.currentMatch, 1, "Should be on first match")
    }

    /// findNext with matchCount == 0 must be a no-op (not crash or misbehave)
    func testFindNextWithZeroMatchesIsNoOp() {
        loadRendererAndRender("hello world")

        // Don't call find() first — simulates the broken FolderWindowContent path
        XCTAssertEqual(findController.matchCount, 0)
        findController.findNext()
        XCTAssertEqual(findController.matchCount, 0, "findNext with no matches must be a no-op")
        XCTAssertEqual(findController.currentMatch, 0, "currentMatch must stay 0")
    }

    /// findPrevious with matchCount == 0 must be a no-op
    func testFindPreviousWithZeroMatchesIsNoOp() {
        loadRendererAndRender("hello world")

        XCTAssertEqual(findController.matchCount, 0)
        findController.findPrevious()
        XCTAssertEqual(findController.matchCount, 0, "findPrevious with no matches must be a no-op")
        XCTAssertEqual(findController.currentMatch, 0, "currentMatch must stay 0")
    }

    /// Case-insensitive search must find matches regardless of case
    func testFindIsCaseInsensitive() {
        loadRendererAndRender("Hello HELLO hello hElLo")

        let expectation = XCTestExpectation(description: "Find completes")
        findController.find("hello")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 4, "Case-insensitive search should find 4 matches")
    }

    /// find() with nil webView must not crash and must clear state
    func testFindWithNilWebViewClears() {
        findController.webView = nil
        findController.find("anything")

        XCTAssertEqual(findController.matchCount, 0)
        XCTAssertEqual(findController.currentMatch, 0)
        XCTAssertEqual(findController.searchText, "")
    }

    /// find() with empty string must clear state
    func testFindWithEmptyStringClears() {
        loadRendererAndRender("some content here")

        // First do a successful search
        let expectation1 = XCTestExpectation(description: "First find completes")
        findController.find("some")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 5.0)
        XCTAssertEqual(findController.matchCount, 1)

        // Now search for empty string — should clear
        findController.find("")
        XCTAssertEqual(findController.matchCount, 0, "Empty search should clear matchCount")
        XCTAssertEqual(findController.currentMatch, 0, "Empty search should clear currentMatch")
        XCTAssertEqual(findController.searchText, "", "Empty search should clear searchText")
    }

    /// Searching for a new term after a previous search must update results
    func testFindReplacesExistingSearch() {
        loadRendererAndRender("apple banana apple cherry banana")

        let expectation1 = XCTestExpectation(description: "First find completes")
        findController.find("apple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 5.0)
        XCTAssertEqual(findController.matchCount, 2, "Should find 2 apples")

        let expectation2 = XCTestExpectation(description: "Second find completes")
        findController.find("banana")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 5.0)
        XCTAssertEqual(findController.matchCount, 2, "Should find 2 bananas")
        XCTAssertEqual(findController.currentMatch, 1, "Should reset to first match")
    }

    /// Searching with special regex characters must work (characters are escaped)
    func testFindWithSpecialCharacters() {
        loadRendererAndRender("price is $100 and $200")

        let expectation = XCTestExpectation(description: "Find completes")
        findController.find("$")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(findController.matchCount, 2, "Special regex char '$' should be escaped and find 2 matches")
    }
}

private class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    var onError: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        onError?(error)
    }
}
