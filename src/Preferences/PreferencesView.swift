import SwiftUI

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

public struct PreferencesView: View {
    @State private var selectedSection: PreferencesSection = .general

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(PreferencesSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 120, ideal: 140, max: 180)
        } detail: {
            detailView(for: selectedSection)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .navigationSplitViewStyle(.balanced)
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
                Toggle("Show gutter markers", isOn: $prefs.printShowGutter)
                Toggle("Show line numbers", isOn: $prefs.printShowLineNumbers)
            } header: {
                Text("Content")
            }

            Section {
                HStack {
                    Text("Margin")
                    Slider(value: $prefs.printMargin, in: 18...72, step: 1)
                    Text("\(Int(prefs.printMargin)) pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            } header: {
                Text("Layout")
            }
        }
        .formStyle(.grouped)
    }
}
