import AppKit
import WebKit
import PDFKit
import CoreGraphics
import os.log

/// Exports WebView content to PDF without showing a print dialog
public final class PDFExporter {

    fileprivate static let logger = Logger(subsystem: "com.redmargin", category: "PDFExporter")

    private struct ExportRunContext {
        let outputURL: URL
        let cssClasses: [String]
        let theme: String
        let completion: (ExportResult) -> Void
    }

    /// Result of a PDF export operation
    public enum ExportResult {
        case success(URL)
        case failure(Error)
    }

    /// Errors that can occur during PDF export
    public enum ExportError: LocalizedError {
        case downloadsNotFound
        case noWindow
        case pdfCreationFailed(String)
        case fileWriteFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .downloadsNotFound:
                return "Could not find Downloads folder"
            case .noWindow:
                return "No window available for export"
            case .pdfCreationFailed(let message):
                return "Failed to create PDF: \(message)"
            case .fileWriteFailed(let error):
                return "Failed to write PDF file: \(error.localizedDescription)"
            }
        }
    }

    /// Exports WebView content to PDF in the Downloads folder using print infrastructure
    /// - Parameters:
    ///   - webView: The WKWebView containing rendered content
    ///   - filename: Base filename (without extension) for the PDF
    ///   - theme: Current theme ("light" or "dark") to preserve in PDF
    ///   - printMargin: Left/right margin in points
    ///   - completion: Called with the result of the export
    public static func export(
        webView: WKWebView,
        filename: String,
        theme: String,
        printMargin: CGFloat = 28,
        completion: @escaping (ExportResult) -> Void
    ) {
        // Need a window for the print operation
        guard let window = webView.window ?? NSApp.keyWindow else {
            completion(.failure(ExportError.noWindow))
            return
        }

        // Get Downloads directory
        guard let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            completion(.failure(ExportError.downloadsNotFound))
            return
        }

        // Generate unique filename
        let outputURL = uniqueFileURL(in: downloadsURL, baseName: filename, extension: "pdf")
        let exportContext = ExportRunContext(
            outputURL: outputURL,
            cssClasses: buildCSSClasses(theme: theme),
            theme: theme,
            completion: completion
        )

        // For dark theme, we use post-processing to fill the background.
        // We set the document background just for the content area.
        let bgColor = theme == "dark" ? "#1a1a1a" : "white"
        let mermaidTheme = theme == "dark" ? "dark" : "default"

        let classStatements = exportContext.cssClasses.map {
            "document.documentElement.classList.add('\($0)'); document.body.classList.add('\($0)');"
        }.joined()

        let prepareJS = """
        (function() {
            // Add CSS classes
            \(classStatements)

            // Set backgrounds directly
            document.documentElement.style.background = '\(bgColor)';
            document.body.style.background = '\(bgColor)';
        })();
        """

        webView.evaluateJavaScript(prepareJS) { _, error in
            if let error = error {
                logger.error("Failed to prepare PDF export styles: \(error.localizedDescription, privacy: .public)")
            }

            webView.callAsyncJavaScript(
                "window.MermaidRenderer ? window.MermaidRenderer.prepareMermaidForPrint(theme) : Promise.resolve()",
                arguments: ["theme": mermaidTheme],
                in: nil,
                in: .page
            ) { result in
                if case .failure(let error) = result {
                    logger.error(
                        "Failed to prepare Mermaid for PDF export: \(error.localizedDescription, privacy: .public)"
                    )
                }

                runExportPrintOperation(
                    webView: webView,
                    window: window,
                    context: exportContext,
                    printMargin: printMargin,
                )
            }
        }
    }

    private static func runExportPrintOperation(
        webView: WKWebView,
        window: NSWindow,
        context: ExportRunContext,
        printMargin: CGFloat
    ) {
        webView.setValue(true, forKey: "drawsBackground")

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)  // A4
        printInfo.topMargin = 56
        printInfo.bottomMargin = 56
        printInfo.leftMargin = printMargin
        printInfo.rightMargin = printMargin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = context.outputURL
        printInfo.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = false

        let printOperation = webView.printOperation(with: printInfo)
        printOperation.showsPrintPanel = false
        printOperation.showsProgressPanel = false

        let handler = PDFExportCompletionHandler(
            webView: webView,
            cssClasses: context.cssClasses,
            outputURL: context.outputURL,
            theme: context.theme,
            completion: context.completion
        )

        objc_setAssociatedObject(printOperation, "pdfHandler", handler, .OBJC_ASSOCIATION_RETAIN)
        printOperation.runModal(
            for: window,
            delegate: handler,
            didRun: #selector(PDFExportCompletionHandler.printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    /// Generates a unique file URL by appending -1, -2, etc. if file exists
    public static func uniqueFileURL(in directory: URL, baseName: String, extension ext: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")

        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }

        return candidate
    }

    /// Builds CSS classes for PDF export based on theme
    public static func buildCSSClasses(theme: String) -> [String] {
        var classes: [String] = []

        // Apply theme class
        if theme == "light" {
            classes.append("print-light-theme")
        } else {
            classes.append("print-dark-theme")
        }

        // Keep gutter (git bars, red margin) and line numbers visible in PDF
        // They will be shown exactly as displayed in the app

        return classes
    }

}

private class PDFExportCompletionHandler: NSObject {
    private let webView: WKWebView
    private let cssClasses: [String]
    private let outputURL: URL
    private let theme: String
    private let completion: (PDFExporter.ExportResult) -> Void

    init(
        webView: WKWebView,
        cssClasses: [String],
        outputURL: URL,
        theme: String,
        completion: @escaping (PDFExporter.ExportResult) -> Void
    ) {
        self.webView = webView
        self.cssClasses = cssClasses
        self.outputURL = outputURL
        self.theme = theme
        self.completion = completion
        super.init()
    }

    @objc func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        // Restore WebView state
        webView.setValue(false, forKey: "drawsBackground")
        let removeStatements = cssClasses.map {
            "document.documentElement.classList.remove('\($0)'); document.body.classList.remove('\($0)');"
        }.joined()
        let cleanupJS = """
        (function() {
            // Remove CSS classes
            \(removeStatements)

            // Reset inline styles
            document.documentElement.style.background = '';
            document.body.style.background = '';
        })();
        """
        webView.evaluateJavaScript(cleanupJS) { _, error in
            if let error = error {
                PDFExporter.logger.error(
                    "Failed to clean up PDF export styles: \(error.localizedDescription, privacy: .public)"
                )
                return
            }

            let mermaidTheme = self.theme == "dark" ? "dark" : "default"
            self.webView.callAsyncJavaScript(
                "window.MermaidRenderer ? window.MermaidRenderer.restoreMermaidFromPrint(theme) : Promise.resolve()",
                arguments: ["theme": mermaidTheme],
                in: nil,
                in: .page
            ) { result in
                if case .failure(let error) = result {
                    PDFExporter.logger.error(
                        "Failed to restore Mermaid after PDF export: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        // Check result
        if success && FileManager.default.fileExists(atPath: outputURL.path) {
            // If dark theme, apply background to margins
            if theme == "dark" {
                // #1a1a1a is approx 0.102 grayscale or sRGB (26/255)
                let darkColor = NSColor(srgbRed: 26/255.0, green: 26/255.0, blue: 26/255.0, alpha: 1.0)
                if let error = applyBackground(to: outputURL, color: darkColor) {
                    completion(.failure(PDFExporter.ExportError.fileWriteFailed(error)))
                    return
                }
            }
            completion(.success(outputURL))
        } else {
            completion(.failure(PDFExporter.ExportError.pdfCreationFailed("Export was cancelled or failed")))
        }
    }

    private func applyBackground(to url: URL, color: NSColor) -> Error? {
        guard let document = PDFDocument(url: url) else {
            let info = [NSLocalizedDescriptionKey: "Could not open generated PDF"]
            return NSError(domain: "com.redmargin.pdf", code: 1, userInfo: info)
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { return nil }

        // We will create a new PDF by drawing the old pages onto a background
        let newPDFData = NSMutableData()
        guard let consumer = CGDataConsumer(data: newPDFData as CFMutableData) else {
            let info = [NSLocalizedDescriptionKey: "Could not create data consumer"]
            return NSError(domain: "com.redmargin.pdf", code: 2, userInfo: info)
        }

        // Get media box from first page
        guard let firstPage = document.page(at: 0) else { return nil }
        var mediaBox = firstPage.bounds(for: .mediaBox)

        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            let info = [NSLocalizedDescriptionKey: "Could not create PDF context"]
            return NSError(domain: "com.redmargin.pdf", code: 3, userInfo: info)
        }

        // Process each page
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            var pageBounds = page.bounds(for: .mediaBox)

            context.beginPage(mediaBox: &pageBounds)

            // Draw background
            context.setFillColor(color.cgColor)
            context.fill(pageBounds)

            // Draw original page content
            // We use the page's drawing method which renders the page content
            page.draw(with: .mediaBox, to: context)

            context.endPage()
        }

        context.closePDF()

        // Write back to file
        do {
            try newPDFData.write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }
}
