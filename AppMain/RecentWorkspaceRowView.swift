import AppKit
import RedmarginCore
import SwiftUI

struct RecentWorkspaceRowView: View {
    let item: RecentWorkspaceItem
    let isSelected: Bool
    let isFocused: Bool
    let isUnavailable: Bool
    let gitSummary: GitWorkspaceSummary?
    let reachability: RemoteReachability
    let onOpen: () -> Void
    let onRetry: () -> Void
    let onPinToggle: () -> Void
    let onRemove: () -> Void
    let onLocate: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stateDot
            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.redmarginRed : Color.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    fusedToken
                    Spacer(minLength: 16)
                    Text(relativeDateText)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .opacity(isHovered ? 0 : 1)
                }

                metaLine
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.redmarginRed)
                    .padding(.top, 4)
                    .opacity(isHovered ? 0 : 1)
            }

            if isFocused {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.redmarginRed)
                    .padding(.top, 4)
                    .opacity(isHovered ? 0 : 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selectionBackground)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                hoverActions
                    .padding(.top, 5)
                    .padding(.trailing, 12)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(item.lastFailureReason ?? item.locationText)
        .contextMenu {
            Button("Open", action: onOpen)
                .disabled(isUnavailable && item.localURL != nil)
            Button(item.isPinned ? "Unpin" : "Pin", action: onPinToggle)
            if item.localURL != nil, !isUnavailable {
                Button("Reveal in Finder", action: revealInFinder)
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyPath, forType: .string)
            }
            if item.localURL != nil && isUnavailable {
                Button("Locate...", action: onLocate)
            }
            if item.remoteLocation != nil && item.lastFailureReason != nil {
                Button("Try Again", action: onRetry)
            }
            Divider()
            Button("Remove", action: onRemove)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAction(named: "Open", onOpen)
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin", onPinToggle)
        .accessibilityAction(named: "Remove", onRemove)
        .accessibilityAction(named: "Reveal in Finder", revealInFinder)
        .accessibilityAction(named: "Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyPath, forType: .string)
        }
        .accessibilityAction(named: "Locate", onLocate)
        .accessibilityAction(named: "Try Again", onRetry)
        .onTapGesture(count: 2, perform: onOpen)
    }

    private var stateDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            .padding(.top, 7)
            .accessibilityHidden(true)
    }

    private var dotColor: Color {
        switch item.availability(remoteReachability: reachability) {
        case .available: return .gutterAdded
        case .idle: return Color.secondary.opacity(0.5)
        case .unavailable: return .gutterDeleted
        }
    }

    private var fusedToken: some View {
        HStack(spacing: 0) {
            if let machine = item.machineToken {
                Text(machine)
                    .foregroundStyle(Color.redmarginRed)
                Text(":")
                    .foregroundStyle(.tertiary)
            }
            Text(item.repoSlug)
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
    }

    @ViewBuilder
    private var metaLine: some View {
        switch item.meta(gitSummary: gitSummary) {
        case .warning(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.gutterDeleted)
        case .containingPath(let path):
            Text(path)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .git(let branch, let changedCount):
            HStack(spacing: 6) {
                Text(branch)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                if changedCount == 0 {
                    Text("clean")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(changedCount) modified")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        case nil:
            EmptyView()
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            HoverActionButton(symbol: item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? "Unpin" : "Pin", action: onPinToggle)
            if item.localURL != nil, !isUnavailable {
                HoverActionButton(symbol: "arrow.up.forward", help: "Reveal in Finder", action: revealInFinder)
            }
            HoverActionButton(symbol: "xmark", help: "Remove", action: onRemove)
        }
    }

    private struct HoverActionButton: View {
        let symbol: String
        let help: String
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? Color.redmarginRed : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHovered
                                ? Color.redmarginRed.opacity(0.15)
                                : Color(nsColor: .quaternarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(help)
        }
    }

    private func revealInFinder() {
        guard let url = item.localURL, !isUnavailable else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var iconName: String {
        item.kind.isFile ? "doc.text" : "folder"
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.redmarginRed.opacity(0.16) : .clear)
    }

    private var relativeDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(item.lastOpened) {
            return "Today, " + item.lastOpened.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(item.lastOpened) {
            return "Yesterday"
        }
        return item.lastOpened.relativeFullDescription
    }

    private var copyPath: String {
        if let url = item.localURL {
            return url.path
        }
        return item.remoteLocation?.displayString ?? item.locationText
    }

    private var accessibilityRowLabel: String {
        let machine = item.machineToken ?? "this Mac"
        return "\(item.repoSlug) on \(machine), \(item.kindLabel.lowercased())"
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if item.isPinned { values.append("Pinned") }
        if isUnavailable { values.append("Unavailable") }
        return values.joined(separator: ", ")
    }
}
