import SwiftUI
import AppKit

// MARK: - Number TextField with Arrow Key Support

struct NumberTextField: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.alignment = .right
        textField.bezelStyle = .roundedBezel
        textField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
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
            guard let textField = obj.object as? NSTextField,
                  let newValue = Double(textField.stringValue) else { return }
            parent.value = min(max(newValue, parent.range.lowerBound), parent.range.upperBound)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                adjustValue(by: parent.step)
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                adjustValue(by: -parent.step)
                return true
            }
            return false
        }

        private func adjustValue(by delta: Double) {
            let newValue = min(max(parent.value + delta, parent.range.lowerBound), parent.range.upperBound)
            parent.value = newValue
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
        case .print: return "Print"
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
            .frame(minWidth: 120)
        } detail: {
            detailView(for: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 450, minHeight: 300)
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
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Non-repository files", selection: $prefs.gutterVisibilityForNonRepo) {
                    Text("Show empty gutter").tag(GutterVisibility.showEmpty)
                    Text("Hide gutter").tag(GutterVisibility.hide)
                }
            } header: {
                Text("Git Gutter")
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
                HStack {
                    Text("Margin")
                    Spacer()
                    NumberTextField(value: $prefs.printMargin, range: 0...144, step: 1)
                        .frame(width: 50, height: 22)
                    Text("pt")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Layout")
            }
        }
        .formStyle(.grouped)
    }
}
