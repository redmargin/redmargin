import SwiftUI

public struct FindBar: View {
    @Binding var searchText: String
    @Binding var isVisible: Bool
    var matchCount: Int
    var currentMatch: Int
    var focusTrigger: UUID
    var onFindNext: () -> Void
    var onFindPrevious: () -> Void
    var onDismiss: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    public init(
        searchText: Binding<String>,
        isVisible: Binding<Bool>,
        matchCount: Int = 0,
        currentMatch: Int = 0,
        focusTrigger: UUID = UUID(),
        onFindNext: @escaping () -> Void = {},
        onFindPrevious: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self._searchText = searchText
        self._isVisible = isVisible
        self.matchCount = matchCount
        self.currentMatch = currentMatch
        self.focusTrigger = focusTrigger
        self.onFindNext = onFindNext
        self.onFindPrevious = onFindPrevious
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Find", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onFindNext()
                    }
                    .onKeyPress(.escape) {
                        onDismiss()
                        return .handled
                    }

                if !searchText.isEmpty {
                    Text(matchCountText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            Button(action: onFindPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .help("Find Previous (Cmd+Shift+G)")

            Button(action: onFindNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .help("Find Next (Cmd+G)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close (Escape)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onAppear {
            isTextFieldFocused = true
        }
        .onChange(of: focusTrigger) { _, _ in
            isTextFieldFocused = true
        }
    }

    private var matchCountText: String {
        if searchText.isEmpty {
            return ""
        } else if matchCount == 0 {
            return "No matches"
        } else {
            return "\(currentMatch) of \(matchCount)"
        }
    }
}
