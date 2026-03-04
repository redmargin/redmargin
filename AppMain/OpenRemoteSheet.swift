import SwiftUI
import RedmarginCore

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
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
    @State var serverName: String = ""
    @State var isConnecting = false
    @State var connectionStatus: String = "Connecting..."
    @State var errorMessage: String?
    @State var selectedServerIndex: Int?
    @FocusState var isServerFieldFocused: Bool

    // Step 2: File browsing
    @State var connection: SSHConnection?
    @State var currentPath: String = ""
    @State var pathInput: String = ""
    @State var entries: [DirectoryEntry] = []
    @State var isLoadingDirectory = false
    @State var pathHistory: [String] = []
    @State var usePathEntry = false
    @State var manualPath: String = ""
    @State var selectedFileIndex: Int?
    @FocusState var isPathFieldFocused: Bool

    @Binding var recentServers: [String]
    let onServerConnected: (String) -> Void
    let onFileSelected: (SSHConnection, String) async throws -> Void
    let onFolderSelected: ((SSHConnection, String) async throws -> Void)?
    let onDismiss: () -> Void

    enum NavDirection { case upward, downward }

    init(
        recentServers: Binding<[String]>,
        onServerConnected: @escaping (String) -> Void,
        onFileSelected: @escaping (SSHConnection, String) async throws -> Void,
        onFolderSelected: ((SSHConnection, String) async throws -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self._recentServers = recentServers
        self.onServerConnected = onServerConnected
        self.onFileSelected = onFileSelected
        self.onFolderSelected = onFolderSelected
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
        .onKeyPress(.downArrow) { handleArrowNavigation(.downward) }
        .onKeyPress(.upArrow) { handleArrowNavigation(.upward) }
        .onKeyPress(.return) { handleEnterKey() }
        .onKeyPress(keys: [KeyEquivalent("n")], phases: .down) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            return handleArrowNavigation(.downward)
        }
        .onKeyPress(keys: [KeyEquivalent("p")], phases: .down) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            return handleArrowNavigation(.upward)
        }
    }
}
