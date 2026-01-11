import SwiftUI

public struct PrintConfigSheet: View {
    @Binding var config: PrintConfiguration
    var onPrint: () -> Void
    var onCancel: () -> Void

    public init(
        config: Binding<PrintConfiguration>,
        onPrint: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._config = config
        self.onPrint = onPrint
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Content") {
                    Toggle("Include Git gutter", isOn: $config.includeGutter)
                    Toggle("Include line numbers", isOn: $config.includeLineNumbers)
                }

                Section {
                    Text("Documents are always printed using light theme.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Print...") {
                    onPrint()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 320)
    }
}
