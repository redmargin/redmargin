import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let fileURL: URL?

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        loadRenderer(webView: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let theme = colorScheme == .dark ? "dark" : "light"
        let basePath = fileURL?.deletingLastPathComponent().path ?? ""
        let params = RenderParams(markdown: markdown, theme: theme, basePath: basePath)

        if context.coordinator.isLoaded {
            Self.render(webView: webView, params: params)
        } else {
            context.coordinator.pendingRender = params
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

        let webRendererURL = resourceURL.appendingPathComponent("WebRenderer")
        webView.loadFileURL(rendererURL, allowingReadAccessTo: webRendererURL)
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
    }

    struct RenderParams {
        let markdown: String
        let theme: String
        let basePath: String
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded = false
        var pendingRender: RenderParams?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true

            if let pending = pendingRender {
                MarkdownWebView.render(webView: webView, params: pending)
                pendingRender = nil
            }
        }
    }
}
