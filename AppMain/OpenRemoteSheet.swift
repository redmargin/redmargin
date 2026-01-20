import SwiftUI
import RedmarginCore

struct OpenRemoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var connectionString: String
    @State private var isConnecting = false
    @State private var errorMessage: String?

    let recentConnections: [String]
    let onConnect: (String, String) async throws -> Void

    init(
        initialConnectionString: String = "",
        recentConnections: [String],
        onConnect: @escaping (String, String) async throws -> Void
    ) {
        self._connectionString = State(initialValue: initialConnectionString)
        self.recentConnections = recentConnections
        self.onConnect = onConnect
    }

    private var parsedConnection: RemoteConnectionParser.ParsedConnection? {
        RemoteConnectionParser.parse(connectionString)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connect to Server")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Main content
            VStack(alignment: .leading, spacing: 16) {
                // Connection input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remote path:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("user@host:/path/to/file.md", text: $connectionString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isConnecting)
                        .onSubmit {
                            connect()
                        }

                    if let parsed = parsedConnection {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Host: \(parsed.host)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Path: \(parsed.path)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if !connectionString.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Format: user@host:/path/to/file.md or host:/path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Error display
                if let error = errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                // Recent connections
                if !recentConnections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(recentConnections, id: \.self) { connection in
                                    Button(action: {
                                        connectionString = connection
                                    }) {
                                        HStack {
                                            Image(systemName: "clock")
                                                .foregroundColor(.secondary)
                                            Text(connection)
                                                .font(.system(.body, design: .monospaced))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(connectionString == connection ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
            }
            .padding()

            Divider()

            // Footer buttons
            HStack {
                Text("Requires SSH key authentication")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 60)
                    } else {
                        Text("Connect")
                            .frame(width: 60)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedConnection == nil || isConnecting)
            }
            .padding()
        }
        .frame(width: 500, height: recentConnections.isEmpty ? 280 : 420)
    }

    private func connect() {
        guard let parsed = parsedConnection else { return }

        isConnecting = true
        errorMessage = nil

        Task {
            do {
                try await onConnect(parsed.host, parsed.path)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = formatError(error)
                }
            }
        }
    }

    private func formatError(_ error: Error) -> String {
        let message = error.localizedDescription

        if message.contains("Permission denied") || message.contains("publickey") {
            return "SSH authentication failed. Ensure you have SSH keys configured for this host in ~/.ssh/config or ssh-agent."
        }

        if message.contains("Connection refused") || message.contains("No route to host") {
            return "Could not connect to host. Verify the hostname and that SSH is running on the server."
        }

        if message.contains("Could not resolve hostname") {
            return "Unknown host. Check the hostname spelling or verify it's in your SSH config."
        }

        return "Connection failed: \(message)"
    }
}
