import XCTest
import WebKit
@testable import Redmargin

final class MarkdownWebViewTests: XCTestCase {
    private var webView: WKWebView!
    private var navigationDelegate: TestNavigationDelegate!

    /// Get WebRenderer directory from project source (works during tests)
    private var webRendererURL: URL {
        // Use #file to find the project root relative to this test file
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
    }

    override func tearDown() {
        webView = nil
        navigationDelegate = nil
        super.tearDown()
    }

    func testWebViewLoadsRendererHTML() throws {
        let expectation = XCTestExpectation(description: "WebView loads renderer.html")

        let rendererURL = webRendererURL
            .appendingPathComponent("src")
            .appendingPathComponent("renderer.html")

        // Verify the file exists
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: rendererURL.path),
            "renderer.html should exist at \(rendererURL.path)"
        )

        navigationDelegate.onFinish = {
            expectation.fulfill()
        }

        navigationDelegate.onError = { error in
            XCTFail("Navigation failed with error: \(error)")
            expectation.fulfill()
        }

        let accessURL = URL(fileURLWithPath: "/")
        webView.loadFileURL(rendererURL, allowingReadAccessTo: accessURL)

        wait(for: [expectation], timeout: 10.0)

        // Verify no JS errors by checking that window.App exists
        let jsExpectation = XCTestExpectation(description: "Check window.App exists")
        webView.evaluateJavaScript("typeof window.App") { result, error in
            XCTAssertNil(error, "Should not have JS error: \(String(describing: error))")
            XCTAssertEqual(result as? String, "object", "window.App should be an object")
            jsExpectation.fulfill()
        }

        wait(for: [jsExpectation], timeout: 5.0)
    }

    func testRenderCallReturnsWithoutError() throws {
        let loadExpectation = XCTestExpectation(description: "WebView loads")

        let rendererURL = webRendererURL
            .appendingPathComponent("src")
            .appendingPathComponent("renderer.html")

        navigationDelegate.onFinish = {
            loadExpectation.fulfill()
        }

        navigationDelegate.onError = { error in
            XCTFail("Navigation failed with error: \(error)")
            loadExpectation.fulfill()
        }

        let accessURL = URL(fileURLWithPath: "/")
        webView.loadFileURL(rendererURL, allowingReadAccessTo: accessURL)

        wait(for: [loadExpectation], timeout: 10.0)

        // Call render with simple markdown
        let renderExpectation = XCTestExpectation(description: "Render completes without error")

        let payload: [String: Any] = [
            "markdown": "# Hello World\n\nThis is a test.",
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
            XCTAssertNil(error, "Render should not throw error: \(String(describing: error))")
            renderExpectation.fulfill()
        }

        wait(for: [renderExpectation], timeout: 5.0)

        // Verify content was rendered by checking for the heading
        let verifyExpectation = XCTestExpectation(description: "Verify rendered content")

        webView.evaluateJavaScript("document.querySelector('h1')?.textContent") { result, error in
            XCTAssertNil(error, "Query should not error")
            XCTAssertEqual(result as? String, "Hello World", "Heading should be rendered")
            verifyExpectation.fulfill()
        }

        wait(for: [verifyExpectation], timeout: 5.0)
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
