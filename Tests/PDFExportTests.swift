import XCTest
@testable import RedmarginLib

final class PDFExportTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Unique Filename Tests

    func testUniqueFileURL_NoExistingFile_ReturnsBasename() {
        let url = PDFExporter.uniqueFileURL(in: tempDirectory, baseName: "document", extension: "pdf")

        XCTAssertEqual(url.lastPathComponent, "document.pdf")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, tempDirectory.standardizedFileURL)
    }

    func testUniqueFileURL_ExistingFile_AppendsSuffix() throws {
        // Create existing file
        let existingFile = tempDirectory.appendingPathComponent("document.pdf")
        try Data().write(to: existingFile)

        let url = PDFExporter.uniqueFileURL(in: tempDirectory, baseName: "document", extension: "pdf")

        XCTAssertEqual(url.lastPathComponent, "document-1.pdf")
    }

    func testUniqueFileURL_MultipleExistingFiles_IncrementsCounter() throws {
        // Create multiple existing files
        try Data().write(to: tempDirectory.appendingPathComponent("document.pdf"))
        try Data().write(to: tempDirectory.appendingPathComponent("document-1.pdf"))
        try Data().write(to: tempDirectory.appendingPathComponent("document-2.pdf"))

        let url = PDFExporter.uniqueFileURL(in: tempDirectory, baseName: "document", extension: "pdf")

        XCTAssertEqual(url.lastPathComponent, "document-3.pdf")
    }

    func testUniqueFileURL_GapInSequence_FillsGap() throws {
        // Create files with a gap: document.pdf, document-2.pdf (missing document-1.pdf)
        try Data().write(to: tempDirectory.appendingPathComponent("document.pdf"))
        try Data().write(to: tempDirectory.appendingPathComponent("document-2.pdf"))

        let url = PDFExporter.uniqueFileURL(in: tempDirectory, baseName: "document", extension: "pdf")

        // Should fill the gap at -1
        XCTAssertEqual(url.lastPathComponent, "document-1.pdf")
    }

    func testUniqueFileURL_DifferentExtension_ReturnsBasename() throws {
        // Create existing .pdf file but request .txt
        try Data().write(to: tempDirectory.appendingPathComponent("document.pdf"))

        let url = PDFExporter.uniqueFileURL(in: tempDirectory, baseName: "document", extension: "txt")

        XCTAssertEqual(url.lastPathComponent, "document.txt")
    }

    // MARK: - CSS Classes Tests

    func testBuildCSSClasses_LightTheme_IncludesLightClass() {
        let classes = PDFExporter.buildCSSClasses(theme: "light")

        XCTAssertTrue(classes.contains("print-light-theme"))
        XCTAssertFalse(classes.contains("print-dark-theme"))
    }

    func testBuildCSSClasses_DarkTheme_IncludesDarkClass() {
        let classes = PDFExporter.buildCSSClasses(theme: "dark")

        XCTAssertTrue(classes.contains("print-dark-theme"))
        XCTAssertFalse(classes.contains("print-light-theme"))
    }

    func testBuildCSSClasses_NeverHidesGutterAndLineNumbers() {
        let lightClasses = PDFExporter.buildCSSClasses(theme: "light")
        let darkClasses = PDFExporter.buildCSSClasses(theme: "dark")

        XCTAssertFalse(lightClasses.contains("print-hide-gutter"))
        XCTAssertFalse(lightClasses.contains("print-hide-line-numbers"))
        XCTAssertFalse(darkClasses.contains("print-hide-gutter"))
        XCTAssertFalse(darkClasses.contains("print-hide-line-numbers"))
    }

    // MARK: - Error Tests

    func testExportError_Descriptions() {
        XCTAssertNotNil(PDFExporter.ExportError.downloadsNotFound.errorDescription)
        XCTAssertTrue(PDFExporter.ExportError.downloadsNotFound.errorDescription!.contains("Downloads"))

        XCTAssertNotNil(PDFExporter.ExportError.noWindow.errorDescription)
        XCTAssertTrue(PDFExporter.ExportError.noWindow.errorDescription!.contains("window"))

        XCTAssertTrue(PDFExporter.ExportError.pdfCreationFailed("Test error").errorDescription!.contains("Test error"))

        let mockError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Write error"])
        XCTAssertTrue(PDFExporter.ExportError.fileWriteFailed(mockError).errorDescription!.contains("Write error"))
    }
}
