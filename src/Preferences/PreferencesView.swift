import SwiftUI

public struct PreferencesView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    public init() {}

    public var body: some View {
        Form {
            Section("Appearance") {
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
            }

            Section("Git Gutter") {
                Picker("Non-repository files", selection: $prefs.gutterVisibilityForNonRepo) {
                    Text("Show empty gutter").tag(GutterVisibility.showEmpty)
                    Text("Hide gutter").tag(GutterVisibility.hide)
                }
            }

            Section("Security") {
                Toggle("Allow remote images", isOn: $prefs.allowRemoteImages)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
