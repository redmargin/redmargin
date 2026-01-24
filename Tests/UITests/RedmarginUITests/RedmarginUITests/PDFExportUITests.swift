import XCTest

final class PDFExportUITests: BaseUITest {

    /// Test dark theme PDF export - just performs the export action
    /// Verification is done by uitest.sh script after test completes
    func testDarkThemePDFExport() throws {
        // File is already open from setUp

        // Switch to dark theme
        pressCharKey("d", modifiers: [.command, .shift])
        sleep(1)

        // Export to PDF (Cmd+E)
        exportToPDF()

        // Test passes if no crash - verification done externally
    }
}
