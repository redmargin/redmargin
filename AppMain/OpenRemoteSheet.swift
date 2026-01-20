import SwiftUI
import RedmarginCore

private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {}

struct OpenRemoteSheet: View {
    // Step 1: Server selection
    @State private var serverName: String = ""
    @State private var isConnecting = false
    @State private var connectionStatus: String = "Connecting..."
    @State private var errorMessage: String?
    @FocusState private var isServerFieldFocused: Bool

    // Step 2: File browsing
    @State private var connection: SSHConnection?
    @State private var currentPath: String = ""
    @State private var pathInput: String = ""
    @State private var entries: [DirectoryEntry] = []
    @State private var isLoadingDirectory = false
    @State private var pathHistory: [String] = []
    @State private var usePathEntry = false
    @State private var manualPath: String = ""
    @FocusState private var isPathFieldFocused: Bool

    @Binding var recentServers: [String]
    let onServerConnected: (String) -> Void
    let onFileSelected: (SSHConnection, String) async throws -> Void
    let onDismiss: () -> Void

    init(
        recentServers: Binding<[String]>,
        onServerConnected: @escaping (String) -> Void,
        onFileSelected: @escaping (SSHConnection, String) async throws -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._recentServers = recentServers
        self.onServerConnected = onServerConnected
        self.onFileSelected = onFileSelected
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if connection == nil {
                serverSelectionView
            } else {
                fileBrowserView
            }

            Divider()
            footer
        }
        .frame(width: 500, height: 450)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if connection != nil {
                Button(action: disconnectAndGoBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
            }

            Text(connection == nil ? "Connect to Server" : "Select File")
                .font(.headline)

            Spacer()

            Button(action: { dismissSheet() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Step 1: Server Selection

    private var serverSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isConnecting {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(connectionStatus)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(serverName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("hostname (from ~/.ssh/config)", text: $serverName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($isServerFieldFocused)
                        .onSubmit { connectToServer() }
                        .onAppear { isServerFieldFocused = true }
                }

                if let error = errorMessage {
                    errorView(error)
                }

                if !recentServers.isEmpty {
                    recentServersView
                }

                Spacer()
            }
        }
        .padding()
    }

    private var recentServersView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(recentServers, id: \.self) { server in
                        HStack {
                            Button(action: {
                                serverName = server
                                connectToServer()
                            }) {
                                HStack {
                                    Image(systemName: "server.rack")
                                        .foregroundColor(.secondary)
                                    Text(server)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                recentServers.removeAll { $0 == server }
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    // MARK: - Step 2: File Browser

    private var fileBrowserView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Path input field
            HStack(spacing: 8) {
                TextField("Path", text: $pathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($isPathFieldFocused)
                    .onSubmit { navigateToPath(pathInput) }
                Button("Go") {
                    navigateToPath(pathInput)
                }
                .disabled(pathInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            if let error = errorMessage {
                errorView(error)
                    .padding()
            }

            if usePathEntry {
                pathEntryView
            } else if isLoadingDirectory {
                Spacer()
                ProgressView()
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                fileList
            }
        }
    }

    private var pathEntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter the path to open:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                TextField("~/path/to/file.md", text: $manualPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { openManualPath() }

                Button("Open") {
                    openManualPath()
                }
                .disabled(manualPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("File browser unavailable - server needs update")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private func openManualPath() {
        let path = manualPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, let conn = connection else { return }

        // Expand ~ to home directory
        let fullPath: String
        if path.hasPrefix("~/") {
            fullPath = currentPath + String(path.dropFirst(1))
        } else if path == "~" {
            fullPath = currentPath
        } else if path.hasPrefix("/") {
            fullPath = path
        } else {
            fullPath = currentPath + "/" + path
        }

        Task {
            do {
                try await onFileSelected(conn, fullPath)
                await MainActor.run {
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to open file: \(error.localizedDescription)"
                }
            }
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Parent directory entry
                if !pathHistory.isEmpty {
                    Button(action: navigateUp) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text("..")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 40)
                }

                ForEach(entries) { entry in
                    Button(action: { selectEntry(entry) }) {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(for: entry.name))
                                .foregroundColor(entry.isDirectory ? .blue : .secondary)
                            Text(entry.name)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            if !entry.isDirectory, let size = entry.size {
                                Text(formatSize(size))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if connection == nil {
                Text("Requires SSH key authentication")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("\(entries.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                dismissSheet()
            }
            .keyboardShortcut(.cancelAction)

            if connection == nil && !isConnecting {
                Button("Connect", action: connectToServer)
                    .keyboardShortcut(.defaultAction)
                    .disabled(serverName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
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

    // MARK: - Actions

    private func connectToServer() {
        let host = serverName.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }

        isConnecting = true
        connectionStatus = "Connecting..."
        errorMessage = nil

        Task {
            do {
                print("[OpenRemoteSheet] Creating SSHConnection for \(host)")
                let conn = SSHConnection(host: host)

                // Save to recent servers immediately (even if connection fails later)
                await MainActor.run {
                    onServerConnected(host)
                }

                print("[OpenRemoteSheet] Calling connect()...")
                try await conn.connect(onProgress: { status in
                    Task { @MainActor in
                        self.connectionStatus = status
                    }
                })
                print("[OpenRemoteSheet] Connected!")

                print("[OpenRemoteSheet] Getting home directory...")
                let homeDir = try await conn.getHomeDirectory()
                print("[OpenRemoteSheet] Home directory: \(homeDir)")

                // Try to list directory with timeout, fall back to path entry if it fails
                var dirEntries: [DirectoryEntry] = []
                var useFallback = false
                do {
                    print("[OpenRemoteSheet] Listing directory...")
                    dirEntries = try await withTimeout(seconds: 5) {
                        try await conn.listDirectory(path: homeDir)
                    }
                    print("[OpenRemoteSheet] Got \(dirEntries.count) entries")
                } catch {
                    print("[OpenRemoteSheet] ListDirectory failed: \(error), using fallback")
                    useFallback = true
                }

                await MainActor.run {
                    self.connection = conn
                    self.currentPath = homeDir
                    self.pathInput = homeDir
                    self.entries = dirEntries
                    self.pathHistory = []
                    self.isConnecting = false
                    self.usePathEntry = useFallback
                    self.isPathFieldFocused = true
                }
            } catch {
                print("[OpenRemoteSheet] ERROR: \(error)")
                await MainActor.run {
                    self.isConnecting = false
                    self.errorMessage = formatError(error)
                }
            }
        }
    }

    private func selectEntry(_ entry: DirectoryEntry) {
        if entry.isDirectory {
            navigateToDirectory(entry.name)
        } else {
            openFile(entry.name)
        }
    }

    private func navigateToDirectory(_ name: String) {
        let newPath: String
        if currentPath == "~" {
            newPath = "~/\(name)"
        } else {
            newPath = "\(currentPath)/\(name)"
        }

        pathHistory.append(currentPath)
        loadDirectory(newPath)
    }

    private func navigateUp() {
        guard let previousPath = pathHistory.popLast() else { return }
        loadDirectory(previousPath)
    }

    private func loadDirectory(_ path: String) {
        guard let conn = connection else { return }

        isLoadingDirectory = true
        errorMessage = nil

        Task {
            do {
                let dirEntries = try await conn.listDirectory(path: path)
                await MainActor.run {
                    self.currentPath = path
                    self.pathInput = path
                    self.entries = dirEntries
                    self.isLoadingDirectory = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingDirectory = false
                    self.errorMessage = "Failed to load directory: \(error.localizedDescription)"
                }
            }
        }
    }

    private func navigateToPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Clear history when jumping to a new path
        pathHistory = [currentPath]
        loadDirectory(trimmed)
    }

    private func openFile(_ name: String) {
        guard let conn = connection else { return }

        let fullPath: String
        if currentPath == "~" {
            fullPath = "~/\(name)"
        } else {
            fullPath = "\(currentPath)/\(name)"
        }

        Task {
            do {
                try await onFileSelected(conn, fullPath)
                await MainActor.run {
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to open file: \(error.localizedDescription)"
                }
            }
        }
    }

    private func disconnectAndGoBack() {
        Task {
            await connection?.disconnect()
        }
        connection = nil
        entries = []
        currentPath = ""
        pathInput = ""
        pathHistory = []
        errorMessage = nil
    }

    private func dismissSheet() {
        Task {
            await connection?.disconnect()
        }
        onDismiss()
    }

    // MARK: - Helpers

    private func formatError(_ error: Error) -> String {
        let message = error.localizedDescription

        if message.contains("Permission denied") || message.contains("publickey") {
            return "SSH authentication failed. Ensure you have SSH keys configured for this host."
        }

        if message.contains("Connection refused") || message.contains("No route to host") {
            return "Could not connect to host. Verify the hostname and that SSH is running."
        }

        if message.contains("Could not resolve hostname") {
            return "Unknown host. Check the hostname or verify it's in your ~/.ssh/config."
        }

        return "Connection failed: \(message)"
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "markdown":
            return "doc.text"
        case "txt":
            return "doc.plaintext"
        default:
            return "doc"
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
