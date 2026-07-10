import XCTest
import PDFKit
import AppKit

final class PDFExportUITests: BaseUITest {

    private struct ExportTimeout: Error, CustomStringConvertible {
        let path: String
        let seconds: TimeInterval
        var description: String { "No PDF appeared at \(path) within \(seconds)s" }
    }

    private struct RenderFailure: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    /// Exporting in dark theme has to produce a readable, complete, actually-dark
    /// PDF. The defect this guards against printed a light band across the top of
    /// the first page, which both the file's existence and its page count survive.
    func testDarkThemePDFExportProducesDarkMultiPagePDF() throws {
        pressCharKey("d", modifiers: [.command, .shift])
        sleep(1)

        exportToPDF()

        let url = try waitForExportedPDF()
        let document = try XCTUnwrap(PDFDocument(url: url), "Exported file at \(url.path) is not a readable PDF")

        XCTAssertGreaterThanOrEqual(
            document.pageCount, 2,
            "The fixture spans two pages; the export must not truncate it"
        )

        let firstPage = try XCTUnwrap(document.page(at: 0), "Exported PDF has no first page")
        let text = firstPage.string ?? ""
        XCTAssertTrue(
            text.contains("Test Document"),
            "First page should carry the document heading. Got: \(text.prefix(120))"
        )
        XCTAssertTrue(
            text.contains("def hello():"),
            "First page should carry the fenced code block"
        )

        let lastPage = try XCTUnwrap(document.page(at: document.pageCount - 1), "Exported PDF has no last page")
        XCTAssertTrue(
            (lastPage.string ?? "").contains("End of document"),
            "Last page should carry the end of the fixture, so no content was dropped"
        )

        let topBrightness = try topEdgeBrightness(of: firstPage)
        XCTAssertLessThan(
            topBrightness, 0.5,
            "Dark-theme export printed a light band across the top of page one (brightness \(topBrightness))"
        )
    }

    // MARK: - Helpers

    /// The app writes the export asynchronously, so wait for the file to appear
    /// and for its size to settle before reading it.
    private func waitForExportedPDF(timeout: TimeInterval = 15) throws -> URL {
        let url = URL(fileURLWithPath: Self.downloadsDir).appendingPathComponent("test.pdf")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let first = fileSize(at: url), first > 0 {
                Thread.sleep(forTimeInterval: 0.3)
                if fileSize(at: url) == first {
                    return url
                }
                continue
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        throw ExportTimeout(path: url.path, seconds: timeout)
    }

    private func fileSize(at url: URL) -> Int? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
    }

    /// Brightness of a pixel just below the top edge, at the horizontal centre of
    /// the page. That is where the light band appeared.
    private func topEdgeBrightness(of page: PDFPage) throws -> CGFloat {
        let bounds = page.bounds(for: .mediaBox)
        let thumbnail = page.thumbnail(of: bounds.size, for: .mediaBox)

        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw RenderFailure(reason: "Could not rasterise the first page for inspection")
        }
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 2 else {
            throw RenderFailure(reason: "Rasterised page is \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        }
        guard let sampled = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2) else {
            throw RenderFailure(reason: "Could not sample the top edge of the first page")
        }
        guard let rgb = sampled.usingColorSpace(.deviceRGB) else {
            throw RenderFailure(reason: "Sampled colour is not convertible to deviceRGB")
        }
        return rgb.brightnessComponent
    }
}
