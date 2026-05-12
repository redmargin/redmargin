import SwiftUI
import AppKit

// MARK: - Number TextField with Arrow Key Support

final class PreferencesNumberTextField: NSTextField {}

struct NumberTextField: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    func makeNSView(context: Context) -> NSTextField {
        let textField = PreferencesNumberTextField()
        textField.delegate = context.coordinator
        textField.alignment = .right
        textField.bezelStyle = .roundedBezel
        textField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.controlSize = .small
        textField.stringValue = "\(Int(value))"
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        let intValue = Int(value)
        if textField.stringValue != "\(intValue)" && !context.coordinator.isEditing {
            textField.stringValue = "\(intValue)"
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumberTextField
        var isEditing = false

        init(_ parent: NumberTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
            guard let textField = obj.object as? NSTextField else { return }
            commitValue(from: textField)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                adjustValue(by: parent.step)
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                adjustValue(by: -parent.step)
                return true
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                commitValue(from: control)
                isEditing = false
                moveFocus(from: control, forward: true)
                return true
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                commitValue(from: control)
                isEditing = false
                moveFocus(from: control, forward: false)
                return true
            }
            return false
        }

        private func adjustValue(by delta: Double) {
            let newValue = min(max(parent.value + delta, parent.range.lowerBound), parent.range.upperBound)
            parent.value = newValue
        }

        private func commitValue(from control: NSControl) {
            guard let textField = control as? NSTextField,
                  let newValue = Double(textField.stringValue) else { return }
            let clampedValue = min(max(newValue, parent.range.lowerBound), parent.range.upperBound)
            parent.value = clampedValue
            textField.stringValue = "\(Int(clampedValue))"
        }

        private func moveFocus(from control: NSControl, forward: Bool) {
            guard let window = control.window,
                  let contentView = window.contentView else {
                return
            }

            let fields = numberFields(in: contentView)
                .filter { !$0.isHidden && $0.isEnabled }
                .sorted(by: visualOrder)
            guard let currentIndex = fields.firstIndex(where: { $0 === control }) else {
                return
            }

            let nextIndex: Int
            if forward {
                nextIndex = fields.index(after: currentIndex) == fields.endIndex ? fields.startIndex : fields.index(after: currentIndex)
            } else {
                nextIndex = currentIndex == fields.startIndex ? fields.index(before: fields.endIndex) : fields.index(before: currentIndex)
            }

            window.makeFirstResponder(fields[nextIndex])
        }

        private func numberFields(in view: NSView) -> [PreferencesNumberTextField] {
            var fields = view.subviews.compactMap { $0 as? PreferencesNumberTextField }
            for subview in view.subviews {
                fields.append(contentsOf: numberFields(in: subview))
            }
            return fields
        }

        private func visualOrder(_ lhs: PreferencesNumberTextField, _ rhs: PreferencesNumberTextField) -> Bool {
            let lhsFrame = lhs.convert(lhs.bounds, to: nil)
            let rhsFrame = rhs.convert(rhs.bounds, to: nil)
            let rowTolerance: CGFloat = 8

            if abs(lhsFrame.midY - rhsFrame.midY) > rowTolerance {
                return lhsFrame.midY > rhsFrame.midY
            }

            return lhsFrame.minX < rhsFrame.minX
        }
    }
}

// MARK: - Preferences Sections

enum PreferencesSection: String, CaseIterable, Identifiable {
    case general
    case print

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .print: return "Print & Export"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .print: return "printer"
        }
    }
}

struct PreferencesView: View {
    @State private var selectedSection: PreferencesSection = .general

    var body: some View {
        NavigationSplitView {
            List(PreferencesSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)
        } detail: {
            detailView(for: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 340)
    }

    @ViewBuilder
    private func detailView(for section: PreferencesSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView()
        case .print:
            PrintSettingsView()
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $prefs.theme) {
                    Text("System").tag(Theme.system)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }

                Picker("Inline Code Color", selection: $prefs.inlineCodeColor) {
                    Text("Warm").tag(InlineCodeColor.warm)
                    Text("Cool").tag(InlineCodeColor.cool)
                    Text("Rose").tag(InlineCodeColor.rose)
                    Text("Purple").tag(InlineCodeColor.purple)
                    Text("Neutral").tag(InlineCodeColor.neutral)
                }

                Picker("Text Width", selection: $prefs.textWidth) {
                    Text("Narrow").tag(TextWidth.narrow)
                    Text("Medium").tag(TextWidth.medium)
                    Text("Wide").tag(TextWidth.wide)
                    Text("Unrestricted").tag(TextWidth.unrestricted)
                }

                Picker("Block Width", selection: $prefs.contentWidth) {
                    Text("Medium").tag(ContentWidth.medium)
                    Text("Wide").tag(ContentWidth.wide)
                    Text("Unrestricted").tag(ContentWidth.unrestricted)
                }
            } header: {
                Text("Appearance (defaults for new documents)")
            }

            Section {
                Toggle("Show gutter by default", isOn: $prefs.showGutter)
                Toggle("Show line numbers by default", isOn: $prefs.showLineNumbers)
                    .disabled(!prefs.showGutter)
                Toggle("Show git indicators by default", isOn: $prefs.showGitIndicators)
                    .disabled(!prefs.showGutter)
            } header: {
                Text("Gutter (defaults for new documents)")
            }

            Section {
                Toggle("Show hidden files", isOn: $prefs.showHiddenFiles)
                Toggle("Show git status indicators", isOn: $prefs.showSidebarGitStatus)
            } header: {
                Text("Sidebar (defaults for new windows)")
            }

            Section {
                Toggle("Allow remote images", isOn: $prefs.allowRemoteImages)
            } header: {
                Text("Security")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrintSettingsView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        Form {
            Section {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        marginField("Top", value: $prefs.printTopMargin)
                        marginField("Right", value: $prefs.printRightMargin)
                    }
                    GridRow {
                        marginField("Bottom", value: $prefs.printBottomMargin)
                        marginField("Left", value: $prefs.printLeftMargin)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Page Margins")
            }

            Section {
                numberRow("Base font size", value: $prefs.printFontSize, range: 10...24, unit: "px")
            } header: {
                Text("Typography")
            }
        }
        .formStyle(.grouped)
    }

    private func marginField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(.secondary)
            NumberTextField(value: value, range: 0...144, step: 1)
                .frame(width: 56, height: 22)
            Text("pt")
                .foregroundStyle(.secondary)
        }
    }

    private func numberRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            NumberTextField(value: value, range: range, step: 1)
                .frame(width: 56, height: 22)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
