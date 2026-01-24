import XCTest
import WebKit
@testable import RedmarginLib

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

final class RemoteAssetSchemeHandlerTests: XCTestCase {

    func testSchemeHandlerInterceptsCustomScheme() throws {
        let expectation = XCTestExpectation(description: "Scheme handler intercepts request")

        // Create a mock fetcher that returns test data
        // Valid 1x1 transparent PNG (70 bytes)
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA" +
            "DUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let testData = Data(base64Encoded: pngBase64)!
        let fetcher: (String) async throws -> (Data, String)? = { path in
            print("[Test] Fetcher called with path: \(path)")
            return (testData, "image/png")
        }

        // Create configuration with scheme handler
        let configuration = WKWebViewConfiguration()
        let schemeHandler = RemoteAssetSchemeHandler(fetchAsset: fetcher)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: RemoteAssetSchemeHandler.scheme)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)

        // Load HTML that references an image with our custom scheme
        let html = """
        <html>
        <body>
        <img id="testImg" src="redmargin-remote:///test/image.png" />
        <script>
        document.getElementById('testImg').onload = function() {
            window.webkit.messageHandlers.testResult.postMessage('loaded');
        };
        document.getElementById('testImg').onerror = function() {
            window.webkit.messageHandlers.testResult.postMessage('error');
        };
        </script>
        </body>
        </html>
        """

        // Add message handler to receive result
        let messageHandler = TestMessageHandler { message in
            print("[Test] Got message: \(message)")
            if message == "loaded" {
                expectation.fulfill()
            } else {
                XCTFail("Image failed to load: \(message)")
                expectation.fulfill()
            }
        }
        configuration.userContentController.add(messageHandler, name: "testResult")

        webView.loadHTMLString(html, baseURL: nil)

        wait(for: [expectation], timeout: 10.0)
    }
}

private class TestMessageHandler: NSObject, WKScriptMessageHandler {
    let onMessage: (String) -> Void

    init(onMessage: @escaping (String) -> Void) {
        self.onMessage = onMessage
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            onMessage(body)
        }
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
