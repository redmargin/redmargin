import AppKit
import WebKit
import os.log

/// Exports WebView content to PDF without showing a print dialog
public final class PDFExporter {

    private static let logger = Logger(subsystem: "com.redmargin", category: "PDFExporter")

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

        // Build CSS classes
        let cssClasses = buildCSSClasses(theme: theme)
        // Add classes to both html and body elements for full coverage
        let prepareJS = cssClasses.map {
            "document.documentElement.classList.add('\($0)'); document.body.classList.add('\($0)');"
        }.joined()

        webView.evaluateJavaScript(prepareJS) { _, _ in
            // Enable background drawing
            webView.setValue(true, forKey: "drawsBackground")

            // Create print info for PDF output
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

            // Configure for PDF file output
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = outputURL

            // Create print operation
            let printOperation = webView.printOperation(with: printInfo)
            printOperation.showsPrintPanel = false
            printOperation.showsProgressPanel = false

            // Create completion handler
            let handler = PDFExportCompletionHandler(
                webView: webView,
                cssClasses: cssClasses,
                outputURL: outputURL,
                completion: completion
            )

            // Store handler to prevent deallocation
            objc_setAssociatedObject(printOperation, "pdfHandler", handler, .OBJC_ASSOCIATION_RETAIN)

            // Run with delegate for proper async handling
            printOperation.runModal(
                for: window,
                delegate: handler,
                didRun: #selector(PDFExportCompletionHandler.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
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

        // Hide gutter and line numbers for cleaner PDF output
        classes.append("print-hide-gutter")
        classes.append("print-hide-line-numbers")

        return classes
    }
}

private class PDFExportCompletionHandler: NSObject {
    private let webView: WKWebView
    private let cssClasses: [String]
    private let outputURL: URL
    private let completion: (PDFExporter.ExportResult) -> Void

    init(
        webView: WKWebView,
        cssClasses: [String],
        outputURL: URL,
        completion: @escaping (PDFExporter.ExportResult) -> Void
    ) {
        self.webView = webView
        self.cssClasses = cssClasses
        self.outputURL = outputURL
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
        let cleanupJS = cssClasses.map {
            "document.documentElement.classList.remove('\($0)'); document.body.classList.remove('\($0)');"
        }.joined()
        webView.evaluateJavaScript(cleanupJS, completionHandler: nil)

        // Check result
        if success && FileManager.default.fileExists(atPath: outputURL.path) {
            completion(.success(outputURL))
        } else {
            completion(.failure(PDFExporter.ExportError.pdfCreationFailed("Export was cancelled or failed")))
        }
    }
}
