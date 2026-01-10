import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let fileURL: URL?
    var onCheckboxToggle: ((Int, Bool) -> Void)?
    var onScrollPositionChange: ((Double) -> Void)?
    var initialScrollPosition: Double
    var showLineNumbers: Bool

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: "checkboxToggle")
        contentController.add(context.coordinator, name: "scrollPosition")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.onCheckboxToggle = onCheckboxToggle
        context.coordinator.onScrollPositionChange = onScrollPositionChange
        context.coordinator.initialScrollPosition = initialScrollPosition

        loadRenderer(webView: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCheckboxToggle = onCheckboxToggle
        context.coordinator.onScrollPositionChange = onScrollPositionChange

        let theme = colorScheme == .dark ? "dark" : "light"
        let basePath = fileURL?.deletingLastPathComponent().path ?? ""
        let params = RenderParams(markdown: markdown, theme: theme, basePath: basePath, scrollPosition: initialScrollPosition)

        if context.coordinator.isLoaded {
            Self.render(webView: webView, params: params)

            // Update line numbers visibility if changed
            if context.coordinator.lastLineNumbersVisible != showLineNumbers {
                context.coordinator.lastLineNumbersVisible = showLineNumbers
                Self.setLineNumbersVisible(webView: webView, visible: showLineNumbers)
            }
        } else {
            context.coordinator.pendingRender = params
            context.coordinator.pendingLineNumbersVisible = showLineNumbers
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadRenderer(webView: WKWebView) {
        guard let resourceURL = Bundle.main.resourceURL else {
            print("Failed to get bundle resource URL")
            return
        }

        let rendererURL = resourceURL
            .appendingPathComponent("WebRenderer")
            .appendingPathComponent("src")
            .appendingPathComponent("renderer.html")

        // Allow read access to root so WebView can load both renderer assets and document images
        let accessURL = URL(fileURLWithPath: "/")
        webView.loadFileURL(rendererURL, allowingReadAccessTo: accessURL)
    }

    static func render(webView: WKWebView, params: RenderParams) {
        let payload: [String: Any] = [
            "markdown": params.markdown,
            "options": [
                "theme": params.theme,
                "basePath": params.basePath
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let escapedJSON = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = "window.App.render(JSON.parse('\(escapedJSON)'))"
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("Render error: \(error)")
            }
        }

        // Restore scroll position after render
        if params.scrollPosition > 0 {
            let scrollScript = "window.ScrollPosition.restore(\(params.scrollPosition))"
            webView.evaluateJavaScript(scrollScript, completionHandler: nil)
        }
    }

    static func setLineNumbersVisible(webView: WKWebView, visible: Bool) {
        let script = "window.LineNumbers.setVisible(\(visible))"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    struct RenderParams {
        let markdown: String
        let theme: String
        let basePath: String
        var scrollPosition: Double = 0
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var isLoaded = false
        var pendingRender: RenderParams?
        var pendingLineNumbersVisible: Bool = true
        var lastLineNumbersVisible: Bool = true
        var onCheckboxToggle: ((Int, Bool) -> Void)?
        var onScrollPositionChange: ((Double) -> Void)?
        var initialScrollPosition: Double = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true

            if let pending = pendingRender {
                MarkdownWebView.render(webView: webView, params: pending)
                pendingRender = nil

                // Apply pending line numbers visibility
                lastLineNumbersVisible = pendingLineNumbersVisible
                MarkdownWebView.setLineNumbersVisible(webView: webView, visible: pendingLineNumbersVisible)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "checkboxToggle",
               let body = message.body as? [String: Any],
               let line = body["line"] as? Int,
               let checked = body["checked"] as? Bool {
                onCheckboxToggle?(line, checked)
            } else if message.name == "scrollPosition",
                      let body = message.body as? [String: Any],
                      let scrollY = body["scrollY"] as? Double {
                onScrollPositionChange?(scrollY)
            }
        }
    }
}
