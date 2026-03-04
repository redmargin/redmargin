import SwiftUI
import RedmarginCore

// MARK: - Header and Footer Views

extension OpenRemoteSheet {
    var header: some View {
        HStack {
            if connection != nil {
                Button(action: disconnectAndGoBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
            }

            Text(connection == nil ? "Connect to Server" : "Browse Remote")
                .font(.headline)

            Spacer()

            Button(action: { dismissSheet() }, label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
        }
        .padding()
    }

    var footer: some View {
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

            if connection != nil && !isLoadingDirectory && onFolderSelected != nil {
                Button("Open Folder") {
                    openCurrentFolder()
                }
            }

            if connection == nil && !isConnecting {
                Button("Connect", action: connectToServer)
                    .keyboardShortcut(.defaultAction)
                    .disabled(serverName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - Server Selection Views

extension OpenRemoteSheet {
    var serverSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isConnecting {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("\(connectionStatus) \(serverName)...")
                        .font(.body)
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

    var recentServersView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(recentServers.enumerated()), id: \.element) { index, server in
                        HStack {
                            Button(action: {
                                serverName = server
                                connectToServer()
                            }, label: {
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
                            })
                            .buttonStyle(.plain)

                            Button(action: {
                                recentServers.removeAll { $0 == server }
                                if let selected = selectedServerIndex {
                                    if selected >= recentServers.count {
                                        selectedServerIndex = recentServers.isEmpty ? nil : recentServers.count - 1
                                    }
                                }
                            }, label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                            })
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                        .background(
                            selectedServerIndex == index
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                        .cornerRadius(4)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}

// MARK: - File Browser Views

extension OpenRemoteSheet {
    var fileBrowserView: some View {
        VStack(alignment: .leading, spacing: 0) {
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

    var pathEntryView: some View {
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

    var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if currentPath != "/" && !currentPath.isEmpty {
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
                    .background(selectedFileIndex == -1 ? Color.accentColor.opacity(0.2) : Color.clear)
                    Divider().padding(.leading, 40)
                }

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    fileRow(entry: entry, index: index)

                    if index < entries.count - 1 {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
    }

    private func fileRow(entry: DirectoryEntry, index: Int) -> some View {
        Button(action: { selectEntry(entry) }, label: {
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
        })
        .buttonStyle(.plain)
        .background(selectedFileIndex == index ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    func errorView(_ error: String) -> some View {
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
}
