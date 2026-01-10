import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText
}

struct MarkdownDocument: FileDocument {
    var content: String

    static var readableContentTypes: [UTType] {
        [.markdown]
    }

    init(content: String = "") {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
