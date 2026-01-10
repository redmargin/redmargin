import SwiftUI

struct DocumentView: View {
    let document: MarkdownDocument

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0))
            : Color(nsColor: NSColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0))
    }

    private var textColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(red: 0.85, green: 0.85, blue: 0.84, alpha: 1.0))
            : Color(nsColor: NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0))
    }

    private var marginLineColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(red: 0.65, green: 0.25, blue: 0.28, alpha: 0.6))
            : Color(nsColor: NSColor(red: 0.78, green: 0.32, blue: 0.35, alpha: 0.45))
    }

    private var gutterColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(red: 0.45, green: 0.45, blue: 0.47, alpha: 1.0))
            : Color(nsColor: NSColor(red: 0.65, green: 0.63, blue: 0.60, alpha: 1.0))
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                // Red margin line - the signature element
                Rectangle()
                    .fill(marginLineColor)
                    .frame(width: 1.5)
                    .padding(.leading, 44)

                // Content area
                VStack(alignment: .leading, spacing: 0) {
                    Text(document.content)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(textColor)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                        .padding(.trailing, 24)
                        .padding(.vertical, 20)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backgroundColor)
        .frame(minWidth: 500, minHeight: 400)
    }
}
