import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText
}

public struct MarkdownDocument: FileDocument {
    public var content: String

    public static var readableContentTypes: [UTType] {
        [.markdown]
    }

    public init(content: String = "") {
        self.content = content
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = String(data: data, encoding: .utf8) ?? ""
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
