import SwiftUI

struct DocumentView: View {
    let document: MarkdownDocument

    var body: some View {
        ScrollView {
            Text(document.content)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
