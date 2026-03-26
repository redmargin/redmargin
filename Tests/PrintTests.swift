import XCTest
import WebKit
@testable import RedmarginLib

final class PrintTests: XCTestCase {
    private var webView: WKWebView!
    private var navigationDelegate: PrintTestNavigationDelegate!

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
        navigationDelegate = PrintTestNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
    }

    override func tearDown() {
        webView = nil
        navigationDelegate = nil
        super.tearDown()
    }

    private func loadRenderer(markdown: String = "# Test", theme: String = "light") {
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

        renderMarkdown(markdown, theme: theme)
    }

    private func renderMarkdown(_ markdown: String, theme: String = "light") {
        let renderExpectation = XCTestExpectation(description: "Render completes")
        let payload: [String: Any] = [
            "markdown": markdown,
            "options": [
                "theme": theme,
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

    private func waitForJavaScriptCondition(
        _ script: String,
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTestExpectation(description: "Wait for JavaScript condition")
        let deadline = Date().addingTimeInterval(timeout)

        func poll() {
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    XCTFail("JavaScript condition failed: \(error)", file: file, line: line)
                    expectation.fulfill()
                    return
                }

                if let value = result as? Bool, value {
                    expectation.fulfill()
                    return
                }

                if Date() >= deadline {
                    XCTFail("Timed out waiting for JavaScript condition: \(script)", file: file, line: line)
                    expectation.fulfill()
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    poll()
                }
            }
        }

        poll()
        wait(for: [expectation], timeout: timeout + 1.0)
    }

    private func evaluateJavaScriptValue(
        _ script: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Any? {
        let expectation = XCTestExpectation(description: "Evaluate JavaScript")
        var output: Any?

        webView.evaluateJavaScript(script) { result, error in
            XCTAssertNil(error, "JavaScript evaluation failed: \(String(describing: error))", file: file, line: line)
            output = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        return output
    }

    private func mermaidColorSignature() -> String {
        let script = """
        (function() {
            var svg = document.querySelector('.mermaid-block > svg');
            if (!svg) return '';
            var matches = svg.outerHTML.match(/#(?:[0-9a-fA-F]{3,8})|rgba?\\([^)]*\\)/g) || [];
            return JSON.stringify(Array.from(new Set(matches)).sort());
        })()
        """

        return evaluateJavaScriptValue(script) as? String ?? ""
    }

    private func mermaidBlockBackgroundColor() -> String {
        let script = """
        (function() {
            var block = document.querySelector('.mermaid-block');
            return block ? getComputedStyle(block).backgroundColor : '';
        })()
        """

        return evaluateJavaScriptValue(script) as? String ?? ""
    }

    private func waitForMermaidColorSignature(
        _ expected: String,
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTestExpectation(description: "Wait for Mermaid colors")
        let deadline = Date().addingTimeInterval(timeout)

        func poll() {
            let current = mermaidColorSignature()
            if current == expected {
                expectation.fulfill()
                return
            }

            if Date() >= deadline {
                XCTFail("Timed out waiting for Mermaid colors to match expected signature", file: file, line: line)
                expectation.fulfill()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                poll()
            }
        }

        poll()
        wait(for: [expectation], timeout: timeout + 1.0)
    }

    // MARK: - PrintConfiguration Tests

    func testPrintConfigurationDefaults() {
        let config = PrintConfiguration.default

        XCTAssertTrue(config.includeGutter, "Default config should include gutter")
        XCTAssertFalse(config.includeLineNumbers, "Default config should not include line numbers")
    }

    func testPrintConfigurationCustomValues() {
        let config = PrintConfiguration(includeGutter: false, includeLineNumbers: true)

        XCTAssertFalse(config.includeGutter, "Custom config should not include gutter")
        XCTAssertTrue(config.includeLineNumbers, "Custom config should include line numbers")
    }

    // MARK: - WebView Print Class Tests

    func testPreparePrintAddsLightThemeClass() {
        loadRenderer()

        let expectation = XCTestExpectation(description: "preparePrint completes")
        let config = PrintConfiguration.default

        MarkdownWebView.preparePrint(webView: webView, config: config) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Check that print-light-theme class was added
        let checkExpectation = XCTestExpectation(description: "Check class")
        webView.evaluateJavaScript("document.body.classList.contains('print-light-theme')") { result, _ in
            XCTAssertEqual(result as? Bool, true, "Body should have print-light-theme class")
            checkExpectation.fulfill()
        }

        wait(for: [checkExpectation], timeout: 5.0)
    }

    func testPreparePrintHidesGutterWhenConfigured() {
        loadRenderer()

        let expectation = XCTestExpectation(description: "preparePrint completes")
        let config = PrintConfiguration(includeGutter: false, includeLineNumbers: false)

        MarkdownWebView.preparePrint(webView: webView, config: config) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Check that print-hide-gutter class was added
        let checkExpectation = XCTestExpectation(description: "Check class")
        webView.evaluateJavaScript("document.body.classList.contains('print-hide-gutter')") { result, _ in
            XCTAssertEqual(result as? Bool, true, "Body should have print-hide-gutter class")
            checkExpectation.fulfill()
        }

        wait(for: [checkExpectation], timeout: 5.0)
    }

    func testPreparePrintHidesLineNumbersWhenConfigured() {
        loadRenderer()

        let expectation = XCTestExpectation(description: "preparePrint completes")
        // Line numbers are hidden by default (includeLineNumbers: false)
        let config = PrintConfiguration(includeGutter: true, includeLineNumbers: false)

        MarkdownWebView.preparePrint(webView: webView, config: config) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Check that print-hide-line-numbers class was added
        let checkExpectation = XCTestExpectation(description: "Check class")
        webView.evaluateJavaScript("document.body.classList.contains('print-hide-line-numbers')") { result, _ in
            XCTAssertEqual(result as? Bool, true, "Body should have print-hide-line-numbers class")
            checkExpectation.fulfill()
        }

        wait(for: [checkExpectation], timeout: 5.0)
    }

    func testRestoreFromPrintRemovesClasses() {
        loadRenderer()

        // First, prepare for print
        let prepareExpectation = XCTestExpectation(description: "preparePrint completes")
        let config = PrintConfiguration(includeGutter: false, includeLineNumbers: false)

        MarkdownWebView.preparePrint(webView: webView, config: config) {
            prepareExpectation.fulfill()
        }

        wait(for: [prepareExpectation], timeout: 5.0)

        // Now restore
        MarkdownWebView.restoreFromPrint(webView: webView)

        // Wait for JS to execute
        let waitExpectation = XCTestExpectation(description: "Wait for restore")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            waitExpectation.fulfill()
        }
        wait(for: [waitExpectation], timeout: 5.0)

        // Check that all print classes were removed
        let checkExpectation = XCTestExpectation(description: "Check classes removed")
        let script = """
            !document.body.classList.contains('print-light-theme') &&
            !document.body.classList.contains('print-hide-gutter') &&
            !document.body.classList.contains('print-hide-line-numbers')
        """
        webView.evaluateJavaScript(script) { result, _ in
            XCTAssertEqual(result as? Bool, true, "All print classes should be removed")
            checkExpectation.fulfill()
        }

        wait(for: [checkExpectation], timeout: 5.0)
    }

    func testPreparePrintKeepsMermaidDiagramVisible() {
        loadRenderer(
            markdown: """
            ```mermaid
            graph TD
              A-->B
            ```
            """,
            theme: "dark"
        )

        waitForJavaScriptCondition("!!document.querySelector('.mermaid-block > svg')")
        let screenColors = mermaidColorSignature()

        let expectation = XCTestExpectation(description: "preparePrint completes")
        let config = PrintConfiguration(includeGutter: true, includeLineNumbers: false)
        MarkdownWebView.preparePrint(webView: webView, config: config) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        waitForJavaScriptCondition(
            "document.body.classList.contains('print-light-theme') && !!document.querySelector('.mermaid-block > svg')"
        )
        let printColors = mermaidColorSignature()

        XCTAssertNotEqual(
            screenColors,
            printColors,
            "Print preparation should rerender Mermaid to the print theme"
        )
        XCTAssertEqual(
            evaluateJavaScriptValue("document.querySelectorAll('.mermaid-block > svg').length") as? Int,
            1,
            "Mermaid diagram should stay visible during print preparation"
        )
    }

    func testPreparePrintAppliesLightMermaidBlockChromeFromDarkScreenTheme() {
        loadRenderer(
            markdown: """
            ```mermaid
            graph TD
              A-->B
            ```
            """,
            theme: "dark"
        )

        waitForJavaScriptCondition("!!document.querySelector('.mermaid-block > svg')")
        let screenBackground = mermaidBlockBackgroundColor()

        let expectation = XCTestExpectation(description: "preparePrint completes")
        let config = PrintConfiguration(includeGutter: true, includeLineNumbers: false)
        MarkdownWebView.preparePrint(webView: webView, config: config) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        waitForJavaScriptCondition(
            """
            document.body.classList.contains('print-light-theme') &&
            getComputedStyle(document.querySelector('.mermaid-block')).backgroundColor === 'rgb(245, 243, 237)'
            """
        )

        let printBackground = mermaidBlockBackgroundColor()
        XCTAssertEqual(
            screenBackground,
            "rgb(37, 37, 40)",
            "Dark mode Mermaid blocks should start with the dark code-block chrome"
        )
        XCTAssertEqual(
            printBackground,
            "rgb(245, 243, 237)",
            "Print preparation should switch Mermaid blocks to the light print chrome"
        )
        XCTAssertNotEqual(
            printBackground,
            screenBackground,
            "Print preparation should not retain the dark screen block background"
        )
    }

    func testRestoreFromPrintRestoresMermaidScreenTheme() {
        loadRenderer(
            markdown: """
            ```mermaid
            graph TD
              A-->B
            ```
            """,
            theme: "dark"
        )

        waitForJavaScriptCondition("!!document.querySelector('.mermaid-block > svg')")
        let originalColors = mermaidColorSignature()

        let prepareExpectation = XCTestExpectation(description: "preparePrint completes")
        let config = PrintConfiguration(includeGutter: true, includeLineNumbers: false)
        MarkdownWebView.preparePrint(webView: webView, config: config) {
            prepareExpectation.fulfill()
        }
        wait(for: [prepareExpectation], timeout: 5.0)

        let printColors = mermaidColorSignature()
        MarkdownWebView.restoreFromPrint(webView: webView, screenTheme: "dark")
        waitForJavaScriptCondition("!document.body.classList.contains('print-light-theme')")
        waitForMermaidColorSignature(originalColors)

        let restoredColors = mermaidColorSignature()
        XCTAssertEqual(restoredColors, originalColors, "Restore should bring Mermaid colors back to the screen theme")
        XCTAssertNotEqual(restoredColors, printColors, "Restore should not leave Mermaid in the print theme")
    }
}

private class PrintTestNavigationDelegate: NSObject, WKNavigationDelegate {
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
