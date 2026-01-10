import XCTest
import SwiftUI
import UniformTypeIdentifiers
@testable import RedMargin

final class AppShellTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func createTempFile(name: String, content: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func loadDocument(from url: URL) throws -> MarkdownDocument {
        let data = try Data(contentsOf: url)
        let content = String(data: data, encoding: .utf8) ?? ""
        return MarkdownDocument(content: content)
    }

    func testMarkdownDocumentLoadsContent() throws {
        let content = "# Hello World\n\nThis is a test."
        let url = try createTempFile(name: "test.md", content: content)
        let document = try loadDocument(from: url)
        XCTAssertEqual(document.content, content)
    }

    func testMarkdownDocumentHandlesUTF8() throws {
        let content = "# Unicode Test\n\nEmoji: 🎉 ✨ 🚀\nCJK: 你好世界\nAccents: café naïve"
        let url = try createTempFile(name: "unicode.md", content: content)
        let document = try loadDocument(from: url)
        XCTAssertEqual(document.content, content)
    }

    func testMarkdownDocumentHandlesEmptyFile() throws {
        let url = try createTempFile(name: "empty.md", content: "")
        let document = try loadDocument(from: url)
        XCTAssertEqual(document.content, "")
    }

    func testMarkdownDocumentHandlesLargeFile() throws {
        let lines = (1...10000).map { "Line \($0): Lorem ipsum dolor sit amet" }
        let content = lines.joined(separator: "\n")
        let url = try createTempFile(name: "large.md", content: content)
        let document = try loadDocument(from: url)
        XCTAssertEqual(document.content.components(separatedBy: "\n").count, 10000)
    }
}
