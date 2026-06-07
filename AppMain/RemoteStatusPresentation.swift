import SwiftUI

/// Pure mapping from a window's `(connectionPhase, hasContent)` to how the inline
/// status overlay should look. Keeping this a value type with no view dependencies
/// lets the overlay logic be unit-tested without rendering anything.
struct RemoteStatusPresentation: Equatable {
    /// How the status is surfaced over the document.
    enum Style: Equatable {
        /// No overlay at all (the window is connected).
        case none
        /// A small, non-dimming corner pill over readable cached content.
        case pill
        /// A centered placeholder with a subtle backdrop, when there is no
        /// cached content to show behind it.
        case placeholder
    }

    let style: Style
    let label: String
    let symbol: String?
    /// Whether the document content should be dimmed. Always false here: soft and
    /// unavailable states keep the last-seen content fully readable.
    let dimsContent: Bool
    /// Whether the centered placeholder draws its subtle backdrop.
    let showsBackdrop: Bool
    /// Whether a Retry control is offered (only for unavailable states).
    let showsRetry: Bool

    static let hidden = RemoteStatusPresentation(
        style: .none, label: "", symbol: nil,
        dimsContent: false, showsBackdrop: false, showsRetry: false
    )

    init(
        style: Style,
        label: String,
        symbol: String?,
        dimsContent: Bool,
        showsBackdrop: Bool,
        showsRetry: Bool
    ) {
        self.style = style
        self.label = label
        self.symbol = symbol
        self.dimsContent = dimsContent
        self.showsBackdrop = showsBackdrop
        self.showsRetry = showsRetry
    }

    init(_ phase: RemoteConnectionPhase, host: String, hasContent: Bool) {
        switch phase {
        case .connected:
            self = .hidden

        case .onDemand, .connecting:
            // Soft, in-progress states. With cached content visible, a non-dimming
            // corner pill; with nothing to show, a centered placeholder.
            self = RemoteStatusPresentation(
                style: hasContent ? .pill : .placeholder,
                label: "Connecting…",
                symbol: nil,
                dimsContent: false,
                showsBackdrop: !hasContent,
                showsRetry: false
            )

        case .unavailable(let reason):
            self = RemoteStatusPresentation(
                style: hasContent ? .pill : .placeholder,
                label: Self.label(for: reason, host: host),
                symbol: Self.symbol(for: reason),
                dimsContent: false,
                showsBackdrop: !hasContent,
                showsRetry: true
            )
        }
    }

    private static func label(for reason: RemoteUnavailableReason, host: String) -> String {
        switch reason {
        case .noRoute: return "No route to \(host)"
        case .refused: return "Connection refused by \(host)"
        case .authFailed: return "Authentication to \(host) failed"
        case .fileNotFound: return "File no longer on \(host)"
        case .serverError: return "Couldn’t connect to \(host)"
        }
    }

    private static func symbol(for reason: RemoteUnavailableReason) -> String {
        switch reason {
        case .noRoute: return "wifi.slash"
        case .refused: return "bolt.horizontal.circle"
        case .authFailed: return "lock.slash"
        case .fileNotFound: return "doc.questionmark"
        case .serverError: return "exclamationmark.triangle"
        }
    }
}

/// Small, reusable status indicator: a label, an optional SF Symbol, and an
/// optional action button (used for "Retry"). Drawn as a non-dimming pill.
struct RemoteStatusPill: View {
    let label: String
    var symbol: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}
