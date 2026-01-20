import Foundation

public enum SSHConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

public enum SSHConnectionError: Error, LocalizedError, Sendable {
    case connectionTimeout(host: String)
    case handshakeTimeout(host: String)
    case operationTimeout(operation: String)
    case sshProcessFailed(host: String, stderr: String)
    case authenticationFailed(host: String)
    case hostUnreachable(host: String)
    case connectionRefused(host: String)
    case serverNotResponding(host: String)
    case unexpectedDisconnect

    public var errorDescription: String? {
        switch self {
        case .connectionTimeout(let host):
            return "Connection to \(host) timed out. Check that the host is reachable and SSH is running."
        case .handshakeTimeout(let host):
            return "Server on \(host) did not respond. The remote server may not be running or may have crashed."
        case .operationTimeout(let operation):
            return "Operation '\(operation)' timed out. The remote server may be overloaded or unresponsive."
        case .sshProcessFailed(let host, let stderr):
            return "SSH to \(host) failed: \(stderr)"
        case .authenticationFailed(let host):
            return "Authentication to \(host) failed. Check your SSH keys are configured correctly."
        case .hostUnreachable(let host):
            return "Cannot reach \(host). Check your network connection and that the hostname is correct."
        case .connectionRefused(let host):
            return "Connection to \(host) refused. SSH may not be running on the remote host."
        case .serverNotResponding(let host):
            return "Remote server on \(host) is not responding. Try reconnecting."
        case .unexpectedDisconnect:
            return "Connection was unexpectedly closed."
        }
    }
}

public actor SSHConnection {
    private let host: String
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private let streamHandler = RPCStreamHandler()
    private var nextRequestId = 1

    // Event stream
    private var eventContinuation: AsyncStream<Data>.Continuation?
    public nonisolated let events: AsyncStream<Data>

    private var state: SSHConnectionState = .disconnected
    private var isIntentionallyDisconnected = false
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var remoteBinaryPath: String?

    private let deployer = ServerDeployer()

    public init(host: String) {
        self.host = host
        var continuation: AsyncStream<Data>.Continuation?
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    public func getHost() -> String {
        return host
    }

    private var homeDirectory: String?

    public func getHomeDirectory() async throws -> String {
        if let cached = homeDirectory {
            return cached
        }
        // Get home directory via SSH before proxy connection
        let result = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host, "echo $HOME"],
            timeout: 15
        )
        if result.exitCode != 0 {
            throw RPCError.serverError("Failed to get home directory")
        }
        let home = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        homeDirectory = home
        return home
    }

    public func connect(onProgress: (@Sendable (String) -> Void)? = nil) async throws {
        print("[SSHConnection] connect() called for \(host), current state: \(state)")
        if state == .connected {
            print("[SSHConnection] Already connected, returning")
            return
        }
        state = .connecting
        isIntentionallyDisconnected = false

        do {
            try await connectInternal(onProgress: onProgress, isRetry: false)
        } catch let error as SSHConnectionError {
            // Retry on handshake/server issues - the binary might be stale or corrupted
            if case .handshakeTimeout = error {
                print("[SSHConnection] Handshake failed, removing server and retrying...")
                onProgress?("Server not responding, redeploying...")
                await deployer.removeDeployedServer(host: host)
                try await connectInternal(onProgress: onProgress, isRetry: true)
            } else if case .serverNotResponding = error {
                print("[SSHConnection] Server not responding, removing server and retrying...")
                onProgress?("Server not responding, redeploying...")
                await deployer.removeDeployedServer(host: host)
                try await connectInternal(onProgress: onProgress, isRetry: true)
            } else {
                state = .disconnected
                throw error
            }
        } catch {
            print("[SSHConnection] Connection failed: \(error)")
            state = .disconnected
            throw error
        }
    }

    private func connectInternal(onProgress: (@Sendable (String) -> Void)?, isRetry: Bool) async throws {
        do {
            // 1. Ensure server is deployed
            print("[SSHConnection] Deploying server... (retry: \(isRetry))")
            let path = try await deployer.ensureServerDeployed(host: host, onProgress: onProgress)
            self.remoteBinaryPath = path
            print("[SSHConnection] Server deployed at \(path)")

            // 2. Establish connection
            print("[SSHConnection] Establishing connection...")
            onProgress?("Connecting...")
            try await establishConnection()
            state = .connected
            reconnectAttempts = 0
            print("[SSHConnection] Connected to \(host)")
        } catch {
            print("[SSHConnection] Connection failed: \(error)")
            state = .disconnected
            throw error
        }
    }

    private func establishConnection() async throws {
        print("[SSHConnection] establishConnection() starting")
        guard let remoteBinaryPath = remoteBinaryPath else {
            print("[SSHConnection] ERROR: No remote binary path")
            throw SSHConnectionError.serverNotResponding(host: host)
        }

        // Apply overall connection timeout (30 seconds for SSH + handshake)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.establishConnectionInternal(remoteBinaryPath: remoteBinaryPath)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                throw SSHConnectionError.connectionTimeout(host: self.host)
            }

            // Wait for first to complete (success or failure)
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                // Clean up process if timeout
                self.process?.terminate()
                self.process = nil
                throw error
            }
        }
    }

    private func establishConnectionInternal(remoteBinaryPath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        // Add keepalive options to detect dead connections
        // Note: ControlMaster disabled - stale control sockets cause "Session open refused" errors
        let args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            host,
            "\(remoteBinaryPath) proxy --reconnect"
        ]
        process.arguments = args
        print("[SSHConnection] SSH command: ssh \(args.joined(separator: " "))")

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
        self.process = process

        // Collect stderr for error reporting (thread-safe)
        final class StderrCollector: @unchecked Sendable {
            private var data = Data()
            private let lock = NSLock()

            func append(_ newData: Data) {
                lock.lock()
                data.append(newData)
                lock.unlock()
            }

            func getString() -> String {
                lock.lock()
                defer { lock.unlock() }
                return String(data: data, encoding: .utf8) ?? "Unknown error"
            }
        }
        let stderrCollector = StderrCollector()

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrCollector.append(data)
                if let text = String(data: data, encoding: .utf8) {
                    print("[SSHConnection] stderr: \(text)")
                }
            }
        }

        print("[SSHConnection] Starting SSH process...")
        try process.run()
        print("[SSHConnection] SSH process started, PID: \(process.processIdentifier)")

        // Brief wait to catch immediate SSH failures
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Check if process exited immediately (SSH error)
        if !process.isRunning {
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw parseSSHError(stderr: stderrCollector.getString())
        }

        // Start reading loop
        startReading()
        print("[SSHConnection] Reading loop started")

        // Handshake with specific timeout
        print("[SSHConnection] Sending Hello handshake...")
        let hello = HelloPayload(clientVersion: "1.0.0", protocolVersion: 1)

        let responseData: Data
        do {
            responseData = try await send(type: RPCMessageType.hello.rawValue, payload: hello, timeout: 5)
        } catch _ as SSHConnectionError {
            // Check if SSH failed while waiting
            if !process.isRunning {
                errPipe.fileHandleForReading.readabilityHandler = nil
                throw parseSSHError(stderr: stderrCollector.getString())
            }
            throw SSHConnectionError.handshakeTimeout(host: host)
        }

        print("[SSHConnection] Got Hello response, decoding...")
        let response = try JSONDecoder().decode(RPCMessage<HelloResponsePayload>.self, from: responseData)

        guard response.payload.accepted else {
            print("[SSHConnection] Handshake rejected!")
            throw SSHConnectionError.serverNotResponding(host: host)
        }
        print("[SSHConnection] Handshake accepted!")
    }

    private func parseSSHError(stderr: String) -> SSHConnectionError {
        let lower = stderr.lowercased()
        if lower.contains("permission denied") || lower.contains("publickey") {
            return .authenticationFailed(host: host)
        } else if lower.contains("connection refused") {
            return .connectionRefused(host: host)
        } else if lower.contains("no route to host") || lower.contains("network is unreachable") {
            return .hostUnreachable(host: host)
        } else if lower.contains("timed out") || lower.contains("timeout") {
            return .connectionTimeout(host: host)
        } else {
            return .sshProcessFailed(host: host, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func send(type: String, payload: some Codable, timeout: TimeInterval = 10) async throws -> Data {
        print("[SSHConnection] send() type=\(type)")
        if state != .connected && state != .connecting {
            print("[SSHConnection] ERROR: Not in connected/connecting state")
            throw SSHConnectionError.serverNotResponding(host: host)
        }

        let id = nextRequestId
        nextRequestId += 1

        let data = try RPCStreamHandler.encode(id: id, type: type, payload: payload)
        print("[SSHConnection] Encoded message id=\(id), size=\(data.count) bytes")

        guard let stdin = stdinPipe?.fileHandleForWriting else {
            print("[SSHConnection] ERROR: No stdin pipe")
            throw SSHConnectionError.unexpectedDisconnect
        }

        print("[SSHConnection] Writing to stdin...")
        try stdin.write(contentsOf: data)
        print("[SSHConnection] Written, waiting for response id=\(id) with timeout=\(timeout)s...")

        // Wait for response with timeout - poll-based to ensure timeout works
        let deadline = Date().addingTimeInterval(timeout)
        registerPendingRequest(id: id)

        while Date() < deadline {
            // Check if response arrived
            if let response = completedResponses.removeValue(forKey: id) {
                print("[SSHConnection] Got response for id=\(id)")
                return response
            }

            // Check if we got disconnected
            if state != .connected && state != .connecting {
                pendingRequestIds.remove(id)
                throw SSHConnectionError.unexpectedDisconnect
            }

            // Wait a bit before checking again
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Timeout - clean up and throw
        print("[SSHConnection] Timeout waiting for response id=\(id)")
        pendingRequestIds.remove(id)
        completedResponses.removeValue(forKey: id)
        throw SSHConnectionError.operationTimeout(operation: type)
    }

    private var pendingRequestIds: Set<Int> = []
    private var completedResponses: [Int: Data] = [:]

    private func registerPendingRequest(id: Int) {
        pendingRequestIds.insert(id)
    }

    private func completeRequest(id: Int, data: Data) {
        if pendingRequestIds.contains(id) {
            completedResponses[id] = data
            pendingRequestIds.remove(id)
        }
    }

    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else {
            print("[SSHConnection] ERROR: No stdout pipe for reading")
            return
        }

        stdout.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData

            if data.isEmpty {
                print("[SSHConnection] EOF on stdout, disconnecting")
                handle.readabilityHandler = nil
                Task { await self.handleDisconnect() }
                return
            }

            print("[SSHConnection] Received \(data.count) bytes from stdout")
            Task { await self.processIncomingData(data) }
        }
    }

    private func processIncomingData(_ data: Data) {
        let messages = streamHandler.receive(data: data)
        print("[SSHConnection] Parsed \(messages.count) messages from incoming data")
        for msgData in messages {
            if let header = try? JSONDecoder().decode(RPCHeader.self, from: msgData) {
                print("[SSHConnection] Message: type=\(header.type), id=\(header.id?.description ?? "nil")")
                if let id = header.id {
                    if pendingRequestIds.contains(id) {
                        print("[SSHConnection] Completing request id=\(id)")
                        completeRequest(id: id, data: msgData)
                    } else {
                        print("[SSHConnection] WARNING: No pending request for id=\(id)")
                    }
                } else {
                    print("[SSHConnection] Push event received")
                    eventContinuation?.yield(msgData)
                }
            } else {
                print("[SSHConnection] ERROR: Failed to decode message header")
            }
        }
    }

    private func handleDisconnect() {
        // Clear pending requests - the polling loop will detect state change
        pendingRequestIds.removeAll()
        completedResponses.removeAll()

        process?.terminate()
        process = nil

        if !isIntentionallyDisconnected {
            state = .reconnecting
            scheduleReconnect()
        } else {
            state = .disconnected
        }
    }

    private func scheduleReconnect() {
        Task {
            let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
            print("[SSHConnection] Reconnecting in \(delay)s...")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if isIntentionallyDisconnected { return }

            reconnectAttempts += 1
            do {
                try await establishConnection()
                state = .connected
                reconnectAttempts = 0
                print("[SSHConnection] Reconnected!")
            } catch {
                print("[SSHConnection] Reconnection failed: \(error)")
                scheduleReconnect()
            }
        }
    }

    public func disconnect() {
        isIntentionallyDisconnected = true
        process?.terminate()
        process = nil
        state = .disconnected

        // Clear pending - polling loops will detect state change
        pendingRequestIds.removeAll()
        completedResponses.removeAll()
    }

    // MARK: - Convenience Methods

    public func listDirectory(path: String) async throws -> [DirectoryEntry] {
        let responseData = try await send(
            type: RPCMessageType.listDirectory.rawValue,
            payload: ListDirectoryPayload(path: path)
        )
        let response = try JSONDecoder().decode(
            RPCMessage<ListDirectoryResponsePayload>.self,
            from: responseData
        )
        if let error = response.payload.error {
            throw RPCError.serverError(error)
        }
        return response.payload.entries ?? []
    }
}
