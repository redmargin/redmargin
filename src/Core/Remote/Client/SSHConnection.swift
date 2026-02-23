import Foundation
import os.log

// SSHConnectionState, SSHConnectionError, and StderrCollector are in SSHConnectionTypes.swift

private let sshLog = Logger(subsystem: "com.redmargin", category: "SSHConnection")

public actor SSHConnection {
    private let host: String
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private let streamHandler = RPCStreamHandler()
    private var nextRequestId = 1

    // Sync marker that server outputs after shell initialization - we discard everything before this
    private static let syncMarker = "REDMARGIN_SYNC_7f3d9a\n"

    // Event stream
    private var eventContinuation: AsyncStream<Data>.Continuation?
    public nonisolated let events: AsyncStream<Data>

    // Connection state stream
    private var stateContinuation: AsyncStream<SSHConnectionState>.Continuation?
    public nonisolated let stateChanges: AsyncStream<SSHConnectionState>

    private var state: SSHConnectionState = .disconnected {
        didSet {
            if state != oldValue {
                stateContinuation?.yield(state)
            }
        }
    }
    private var isIntentionallyDisconnected = false
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var lastResponseTime = Date()
    private var reconnectTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?
    private var remoteBinaryPath: String?

    private let deployer = ServerDeployer()

    public init(host: String) {
        self.host = host

        var eventCont: AsyncStream<Data>.Continuation?
        var stateCont: AsyncStream<SSHConnectionState>.Continuation?

        self.events = AsyncStream { cont in
            eventCont = cont
        }
        self.stateChanges = AsyncStream { cont in
            stateCont = cont
        }

        self.eventContinuation = eventCont
        self.stateContinuation = stateCont
    }

    public func getHost() -> String {
        return host
    }

    public func getState() -> SSHConnectionState {
        return state
    }

    /// Returns true if the connection state is connected AND the SSH process is still running
    public func isAlive() -> Bool {
        return state == .connected && process?.isRunning == true
    }

    /// Seconds since the last successful RPC response
    public func idleTime() -> TimeInterval {
        Date().timeIntervalSince(lastResponseTime)
    }

    /// Forces an immediate reconnection by killing the current SSH process.
    /// Used when the system wakes from sleep and the TCP connection is likely dead
    /// but the process hasn't detected it yet.
    public func forceReconnect() {
        sshLog.info("forceReconnect() called, state=\(String(describing: self.state), privacy: .public)")
        switch state {
        case .disconnected:
            // Was fully disconnected (e.g. all reconnect attempts exhausted) — restart from scratch
            isIntentionallyDisconnected = false
            reconnectAttempts = 0
            state = .reconnecting
            scheduleReconnect()
        case .reconnecting:
            // Cancel the existing slow reconnect loop and start fresh immediately
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempts = 0
            scheduleReconnect()
        case .connected, .connecting:
            handleDisconnect()
        }
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

        // First attempt
        do {
            try await connectInternal(onProgress: onProgress, isRetry: false)
            return
        } catch let error as SSHConnectionError {
            // Only retry on handshake/timing issues
            switch error {
            case .handshakeTimeout, .serverNotResponding, .connectionTimeout:
                print("[SSHConnection] First attempt failed (\(error)), will retry...")
            default:
                state = .disconnected
                throw error
            }
        } catch {
            print("[SSHConnection] Connection failed: \(error)")
            state = .disconnected
            throw error
        }

        // Quick retry - daemon is likely running, just connect again
        print("[SSHConnection] Quick retry (daemon should be running)...")
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        do {
            try await establishConnection()
            state = .connected
            startHealthCheck()
            print("[SSHConnection] Quick retry succeeded")
            return
        } catch {
            print("[SSHConnection] Quick retry failed: \(error)")
        }

        // Final attempt - full redeploy
        print("[SSHConnection] Full redeploy and retry...")
        onProgress?("Redeploying to")
        await deployer.removeDeployedServer(host: host)
        try await connectInternal(onProgress: onProgress, isRetry: true)
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
            onProgress?("Connecting to")
            try await establishConnection()
            state = .connected
            startHealthCheck()
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
                // Clean up process if timeout - clear file handle callbacks first
                // to prevent race conditions with readabilityHandler closures
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.process?.terminate()
                self.process = nil
                self.stdinPipe = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                throw error
            }
        }
    }

    private func establishConnectionInternal(remoteBinaryPath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        // Add keepalive options to detect dead connections
        // Note: ControlMaster disabled - stale control sockets cause "Session open refused" errors
        // -T disables PTY allocation to reduce shell initialization issues
        let args = [
            "-T",
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
            throw parseSSHStderr(stderrCollector.getString(), host: host)
        }

        // Wait for sync marker - discard any shell initialization output (.bashrc, etc.)
        print("[SSHConnection] Waiting for sync marker...")
        try await waitForSyncMarker(
            stdout: outPipe.fileHandleForReading,
            process: process,
            stderrCollector: stderrCollector,
            errPipe: errPipe)
        print("[SSHConnection] Sync marker received, starting protocol")

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
                throw parseSSHStderr(stderrCollector.getString(), host: host)
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

    /// Waits for the sync marker from the server, discarding any shell initialization output.
    private func waitForSyncMarker(
        stdout: FileHandle,
        process: Process,
        stderrCollector: StderrCollector,
        errPipe: Pipe
    ) async throws {
        let markerData = Data(Self.syncMarker.utf8)
        let maxGarbageBytes = 64 * 1024
        let accumulator = SyncMarkerAccumulator()

        stdout.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task { await accumulator.append(data, marker: markerData) }
            }
        }
        defer { stdout.readabilityHandler = nil }

        let timeoutNanos: UInt64 = 10_000_000_000
        let startTime = DispatchTime.now()

        while true {
            let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            if elapsed > timeoutNanos {
                let preview = await String(data: accumulator.getBuffer().prefix(500), encoding: .utf8) ?? "<binary>"
                print("[SSHConnection] Sync marker timeout. Buffer: \(preview)")
                throw SSHConnectionError.handshakeTimeout(host: host)
            }

            if !process.isRunning {
                errPipe.fileHandleForReading.readabilityHandler = nil
                throw parseSSHStderr(stderrCollector.getString(), host: host)
            }

            let result = await accumulator.getResult()
            if result.found {
                if !result.discarded.isEmpty {
                    let discarded = String(data: result.discarded, encoding: .utf8) ?? "<binary>"
                    print("[SSHConnection] Discarded shell output: \(discarded.prefix(200))")
                }
                if !result.remaining.isEmpty {
                    _ = streamHandler.receive(data: result.remaining)
                }
                return
            }

            let bufferSize = await accumulator.getBuffer().count
            if bufferSize > maxGarbageBytes {
                throw SSHConnectionError.serverNotResponding(host: host)
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    public func send(type: String, payload: some Codable, timeout: TimeInterval = 10) async throws -> Data {
        sshLog.info("send() type=\(type)")
        if state != .connected && state != .connecting {
            sshLog.error("send() rejected: state=\(String(describing: self.state))")
            throw SSHConnectionError.serverNotResponding(host: host)
        }

        let id = nextRequestId
        nextRequestId += 1

        let data = try RPCStreamHandler.encode(id: id, type: type, payload: payload)

        guard let stdin = stdinPipe?.fileHandleForWriting else {
            sshLog.error("send() id=\(id): no stdin pipe")
            throw SSHConnectionError.unexpectedDisconnect
        }

        // Write on a GCD thread so a blocked pipe doesn't freeze the actor.
        // Race it against a 5s timeout — if write blocks that long, the connection is dead.
        sshLog.info("send() id=\(id): writing \(data.count) bytes to stdin...")
        let stdinHandle = stdin
        let writeData = data
        let writeOK: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @Sendable in
                do {
                    try stdinHandle.write(contentsOf: writeData)
                    return true
                } catch {
                    return false
                }
            }
            group.addTask { @Sendable in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return false
            }
            defer { group.cancelAll() }
            return await group.next() ?? false
        }

        guard writeOK else {
            sshLog.error("send() id=\(id): stdin write blocked/failed — forcing reconnect")
            handleDisconnect()
            throw SSHConnectionError.operationTimeout(operation: type)
        }

        sshLog.info("send() id=\(id): written, waiting for response (timeout=\(timeout)s)")

        // Wait for response with timeout - poll-based to ensure timeout works
        let deadline = Date().addingTimeInterval(timeout)
        registerPendingRequest(id: id)

        while Date() < deadline {
            if let response = completedResponses.removeValue(forKey: id) {
                sshLog.info("send() id=\(id): got response")
                return response
            }

            if state != .connected && state != .connecting {
                pendingRequestIds.remove(id)
                throw SSHConnectionError.unexpectedDisconnect
            }

            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Timeout - connection is stale; force reconnect so it recovers
        sshLog.error("send() id=\(id): timeout after \(timeout)s — forcing reconnect")
        pendingRequestIds.remove(id)
        completedResponses.removeValue(forKey: id)
        handleDisconnect()
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
            lastResponseTime = Date()
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
        sshLog.info("handleDisconnect() state=\(String(describing: self.state), privacy: .public)")
        healthCheckTask?.cancel()
        healthCheckTask = nil

        // Clear file handle callbacks first to prevent race conditions
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil

        // Clear pending requests and stale stream data so the next connection starts clean
        pendingRequestIds.removeAll()
        completedResponses.removeAll()
        streamHandler.reset()
        nextRequestId = 1

        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        if !isIntentionallyDisconnected {
            state = .reconnecting
            reconnectTask?.cancel()
            reconnectTask = nil
            scheduleReconnect()
        } else {
            sshLog.info("handleDisconnect() intentional, not reconnecting")
            state = .disconnected
        }
    }

    /// Periodically checks if the SSH process is still alive.
    /// Catches cases where SSH exited (e.g. ServerAliveInterval timeout killed it)
    /// but the readabilityHandler EOF didn't fire.
    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                guard !Task.isCancelled, state == .connected else { continue }
                if process?.isRunning != true {
                    sshLog.error("Health check: SSH process is dead, triggering reconnect")
                    handleDisconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTask = Task {
            let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
            sshLog.info("scheduleReconnect() attempt=\(self.reconnectAttempts) delay=\(delay)s")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled, !isIntentionallyDisconnected else {
                sshLog.info("scheduleReconnect() cancelled or intentionally disconnected")
                return
            }

            reconnectAttempts += 1
            state = .connecting
            do {
                try await establishConnection()
                state = .connected
                startHealthCheck()
                reconnectAttempts = 0
                sshLog.info("Reconnected successfully!")
                NotificationCenter.default.post(
                    name: .sshConnectionReconnected,
                    object: self.host
                )
            } catch {
                guard !Task.isCancelled else { return }
                state = .reconnecting
                sshLog.error("Reconnection failed: \(error.localizedDescription, privacy: .public)")
                scheduleReconnect()
            }
        }
    }

    public func disconnect() {
        isIntentionallyDisconnected = true

        healthCheckTask?.cancel()
        healthCheckTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil

        // Clear file handle callbacks first to prevent race conditions
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil

        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        state = .disconnected

        // Clear pending - polling loops will detect state change
        pendingRequestIds.removeAll()
        completedResponses.removeAll()
    }

}

// MARK: - Convenience Methods

extension SSHConnection {
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

    public func readAsset(path: String) async throws -> (data: Data, mimeType: String) {
        // Longer timeout for large files (images can be several MB)
        let responseData = try await send(
            type: RPCMessageType.readAsset.rawValue,
            payload: ReadAssetPayload(path: path),
            timeout: 60
        )
        let response = try JSONDecoder().decode(
            RPCMessage<ReadAssetResponsePayload>.self,
            from: responseData
        )
        if let error = response.payload.error {
            throw RPCError.serverError(error)
        }
        guard let base64Data = response.payload.data,
              let data = Data(base64Encoded: base64Data) else {
            throw RPCError.serverError("Invalid asset data")
        }
        return (data, response.payload.mimeType ?? "application/octet-stream")
    }
}
