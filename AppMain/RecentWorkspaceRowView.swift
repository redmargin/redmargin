import AppKit
import SwiftUI

struct RecentWorkspaceRowView: View {
    let item: RecentWorkspaceItem
    let isSelected: Bool
    let isFocused: Bool
    let isUnavailable: Bool
    let onOpen: () -> Void
    let onRetry: () -> Void
    let onPinToggle: () -> Void
    let onRemove: () -> Void
    let onLocate: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(item.machineLabel)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)

                    Text(item.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isUnavailable {
                        Label("Unavailable", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }

                HStack(spacing: 4) {
                    Text(item.pathText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(" · ")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text(relativeDateText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isUnavailable && item.localURL != nil && isHovered {
                Button("Locate...", action: onLocate)
                    .controlSize(.small)
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if isFocused {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(item.lastFailureReason ?? item.locationText)
        .contextMenu {
            Button("Open", action: onOpen)
                .disabled(isUnavailable && item.localURL != nil)
            Button(item.isPinned ? "Unpin" : "Pin", action: onPinToggle)
            if let url = item.localURL, !isUnavailable {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
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
        .accessibilityLabel("\(item.displayTitle) on \(item.machineLabel), \(item.kindLabel.lowercased()), at \(item.pathText)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAction(named: "Open", onOpen)
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin", onPinToggle)
        .accessibilityAction(named: "Remove", onRemove)
        .accessibilityAction(named: "Reveal in Finder") {
            if let url = item.localURL, !isUnavailable {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        .accessibilityAction(named: "Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyPath, forType: .string)
        }
        .accessibilityAction(named: "Locate", onLocate)
        .accessibilityAction(named: "Try Again", onRetry)
        .onTapGesture(count: 2, perform: onOpen)
    }

    private var iconName: String {
        if item.kind.isFile { return item.isPinned ? "doc.text.fill" : "doc.text" }
        return item.isPinned ? "folder.fill" : "folder"
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18) : .clear)
    }

    private var relativeDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(item.lastOpened) {
            return "Today, " + item.lastOpened.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(item.lastOpened) {
            return "Yesterday"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: item.lastOpened, relativeTo: Date())
    }

    private var copyPath: String {
        if let url = item.localURL {
            return url.path
        }
        return item.remoteLocation?.displayString ?? item.locationText
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if item.isPinned { values.append("Pinned") }
        if isUnavailable { values.append("Unavailable") }
        return values.joined(separator: ", ")
    }
}
