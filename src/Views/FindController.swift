import Foundation
import WebKit
import Combine

/// Controller for find-in-page functionality
/// Pass this to MarkdownWebView and use it to trigger find operations
public class FindController: ObservableObject {
    @Published public var matchCount: Int = 0
    @Published public var currentMatch: Int = 0
    @Published public var searchText: String = ""

    weak var webView: WKWebView?
    private var lastSearchText: String = ""

    public init() {}

    /// Find text in the web view
    public func find(_ text: String) {
        guard let webView = webView, !text.isEmpty else {
            clearFind()
            return
        }

        searchText = text
        lastSearchText = text

        // Use JavaScript to count matches and highlight
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        // Count matches using regex on text content
        let countScript = """
        (function() {
            const text = '\(escapedText)';
            const content = document.body.innerText;
            const regex = new RegExp(text.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'), 'gi');
            const matches = content.match(regex);
            return matches ? matches.length : 0;
        })()
        """

        webView.evaluateJavaScript(countScript) { [weak self] result, _ in
            guard let self = self else { return }
            if let count = result as? Int {
                self.matchCount = count
                if count > 0 {
                    self.currentMatch = 1
                    // Clear selection and find first match from top
                    self.jumpToFirstMatch()
                } else {
                    self.currentMatch = 0
                }
            }
        }
    }

    /// Find next match
    public func findNext() {
        guard matchCount > 0 else { return }
        performFind(forward: true, wrapAround: true)
        if currentMatch < matchCount {
            currentMatch += 1
        } else {
            currentMatch = 1
        }
    }

    /// Find previous match
    public func findPrevious() {
        guard matchCount > 0 else { return }
        performFind(forward: false, wrapAround: true)
        if currentMatch > 1 {
            currentMatch -= 1
        } else {
            currentMatch = matchCount
        }
    }

    /// Clear find highlights
    public func clearFind() {
        matchCount = 0
        currentMatch = 0
        searchText = ""
        lastSearchText = ""

        // Clear selection
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
    }

    private func jumpToFirstMatch() {
        guard let webView = webView, !lastSearchText.isEmpty else { return }

        let escapedText = lastSearchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        // Clear selection and move to start, then find forward
        let script = """
        (function() {
            window.getSelection().removeAllRanges();
            window.scrollTo(0, 0);
            window.find('\(escapedText)', false, false, true, false, true, false);
        })()
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func performFind(forward: Bool, wrapAround: Bool) {
        guard let webView = webView, !lastSearchText.isEmpty else { return }

        let escapedText = lastSearchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        // window.find(searchText, caseSensitive, backwards, wrapAround, wholeWord, searchInFrames, showDialog)
        let script = "window.find('\(escapedText)', false, \(!forward), \(wrapAround), false, true, false)"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}
