import AppKit
import WebKit

public class PrintManager {

    public static func print(
        webView: WKWebView,
        fileURL: URL,
        config: PrintConfiguration,
        in window: NSWindow,
        completion: @escaping () -> Void
    ) {
        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        // Set margins
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let printOperation = webView.printOperation(with: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true

        // Set job title to file path for identification
        printOperation.jobTitle = fileURL.displayPath

        // Use delegate to handle completion
        let delegate = PrintOperationDelegate(completion: completion)
        printOperation.runModal(
            for: window,
            delegate: delegate,
            didRun: #selector(PrintOperationDelegate.printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )

        // Store delegate to prevent deallocation
        objc_setAssociatedObject(
            printOperation,
            "printDelegate",
            delegate,
            .OBJC_ASSOCIATION_RETAIN
        )
    }
}

private extension URL {
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private class PrintOperationDelegate: NSObject {
    let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    @objc func printOperationDidRun(
        _ printOperation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        completion()
    }
}
