import SwiftUI

@main
struct RedMarginApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            DocumentView(document: file.document)
        }
    }
}
