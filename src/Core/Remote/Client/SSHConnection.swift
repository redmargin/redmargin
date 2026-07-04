import Foundation
#if canImport(os)
import os.log
#endif

// SSHConnectionState, SSHConnectionError, and StderrCollector are in SSHConnectionTypes.swift

// sshLog is defined in SSHConnectionExtensions.swift

public actor SSHConnection {
    let host: String
    var process: Process?
    var stdinPipe: Pipe?
    var stdoutPipe: Pipe?
    var stderrPipe: Pipe?

    let streamHandler = RPCStreamHandler()
    var nextRequestId = 1

    /// Serial queue for stdin writes. Actor reentrancy at await suspension
    /// points allows concurrent send() calls, which could interleave writes
    /// on the pipe and corrupt protocol framing. This queue serializes them.
    private let stdinWriteQueue = DispatchQueue(label: "com.redmargin.ssh.stdin-write")

    // Sync marker that server outputs after shell initialization - we discard everything before this
    private static let syncMarker = "REDMARGIN_SYNC_7f3d9a\n"

    // Event stream
    private var eventContinuation: AsyncStream<Data>.Continuation?
    public nonisolated let events: AsyncStream<Data>

    // Connection state stream
    private var stateContinuation: AsyncStream<SSHConnectionState>.Continuation?
    public nonisolated let stateChanges: AsyncStream<SSHConnectionState>

    var state: SSHConnectionState = .disconnected {
        didSet {
            if state != oldValue {
                stateContinuation?.yield(state)
                // Fan every transition out to all windows on this host. The
                // `stateChanges` stream above is single-consumer, so when several
                // windows share one connection it raffles each transition to just
                // one of them; this broadcast reaches every window's overlay.
                NotificationCenter.default.post(
                    name: .sshConnectionStateChanged,
                    object: host,
                    userInfo: ["state": state]
                )
            }
        }
    }
    var isIntentionallyDisconnected = false
    var reconnectAttempts = 0
    let maxReconnectDelay: TimeInterval = 30.0
    private var lastResponseTime = Date()
    var reconnectTask: Task<Void, Never>?
    var healthCheckTask: Task<Void, Never>?
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

    /// A reusable connection can be force-reconnected rather than replaced.
    /// Only connections intentionally closed via `disconnect()` or `disconnectAll()`
    /// are not reusable — the manager should replace them instead.
    public var isReusable: Bool {
        !isIntentionallyDisconnected
    }

    /// Seconds since the last successful RPC response
    public func idleTime() -> TimeInterval {
        Date().timeIntervalSince(lastResponseTime)
    }

    /// Forces an immediate reconnection by killing the current SSH process.
    /// Used when the system wakes from sleep and the TCP connection is likely dead
    /// but the process hasn't detected it yet.
    public func forceReconnect() {
        #if canImport(os)
        sshLog.info("forceReconnect() called, state=\(String(describing: self.state), privacy: .public)")
        #endif
        switch state {
        case .disconnected:
            // Was fully disconnected (e.g. all reconnect attempts exhausted) — restart from scratch
            isIntentionallyDisconnected = false
            reconnectAttempts = 0
            state = .reconnecting
            if remoteBinaryPath == nil {
                reconnectTask?.cancel()
                reconnectTask = Task { [weak self] in
                    try? await self?.connect(onProgress: nil)
                }
            } else {
                scheduleReconnect()
            }
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

    /// Forces a full restart of the remote Redmargin helper, then reconnects.
    /// Use this when the proxy/socket is reachable but RPCs stop returning:
    /// a plain reconnect can attach to the same wedged daemon.
    public func forceRestartRemoteServer() async throws {
        #if canImport(os)
        sshLog.error("forceRestartRemoteServer() called, state=\(String(describing: self.state), privacy: .public)")
        #endif

        reconnectTask?.cancel()
        reconnectTask = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil
        resetTransportForReconnect()
        isIntentionallyDisconnected = false
        reconnectAttempts = 0
        state = .reconnecting

        await deployer.removeDeployedServer(host: host)
        try await connect(onProgress: nil)
    }

    /// Lays down a fresh, correct-version server binary during a failing reconnect
    /// loop and refreshes `remoteBinaryPath`. A bare `proxy --reconnect` can never
    /// recover from a missing or stale binary (version skew after an app update),
    /// so the reconnect escalation calls this instead of looping forever. Best
    /// effort: a deploy failure (host unreachable) is swallowed so the loop keeps
    /// retrying with backoff. Lives here because `deployer` and `remoteBinaryPath`
    /// are file-private.
    func redeployServerForReconnect() async {
        await deployer.removeDeployedServer(host: host)
        if let path = try? await deployer.ensureServerDeployed(host: host, onProgress: nil) {
            remoteBinaryPath = path
        }
    }

    private func resetTransportForReconnect() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil

        process?.terminateIfRunning()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        pendingRequestIds.removeAll()
        completedResponses.removeAll()
        streamHandler.reset()
        nextRequestId = 1
    }

    private var homeDirectory: String?

    public func getHomeDirectory() async throws -> String {
        if let cached = homeDirectory {
            return cached
        }
        // Get home directory via SSH before proxy connection
        let result = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, "echo $HOME"],
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
        RemoteLog.info("[SSHConnection] connect() called for \(host), current state: \(state)")
        if state == .connected {
            RemoteLog.info("[SSHConnection] Already connected, returning")
            return
        }
        state = .connecting
        isIntentionallyDisconnected = false

        // First attempt
        do {
            try await connectInternal(onProgress: onProgress, isRetry: false)
            return
        } catch let error as SSHConnectionError {
            // The quick-retry-and-redeploy cascade below runs only when SSH reached
            // the host but the helper/handshake misbehaved. A `.connectionTimeout`
            // means we could not even establish SSH (the host is unreachable now), so
            // redeploying is pointless — it joins hard-unreachable, refused, and auth
            // failures in `default` and throws immediately with no retry and no
            // redeploy, so a dead host fails in seconds instead of a minute (T23).
            switch error {
            case .handshakeTimeout, .serverNotResponding, .helperStartupTimeout:
                RemoteLog.info("[SSHConnection] First attempt failed (\(error)), will retry...")
            default:
                state = .disconnected
                throw error
            }
        } catch {
            RemoteLog.info("[SSHConnection] Connection failed: \(error)")
            state = .disconnected
            throw error
        }

        // Quick retry - daemon is likely running, just connect again
        RemoteLog.info("[SSHConnection] Quick retry (daemon should be running)...")
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        do {
            try await establishConnection()
            state = .connected
            startHealthCheck()
            RemoteLog.info("[SSHConnection] Quick retry succeeded")
            return
        } catch {
            RemoteLog.info("[SSHConnection] Quick retry failed: \(error)")
        }

        // Final attempt - full redeploy
        RemoteLog.info("[SSHConnection] Full redeploy and retry...")
        onProgress?("Redeploying to")
        await deployer.removeDeployedServer(host: host)
        try await connectInternal(onProgress: onProgress, isRetry: true)
    }

    private func connectInternal(onProgress: (@Sendable (String) -> Void)?, isRetry: Bool) async throws {
        do {
            // 1. Ensure server is deployed
            RemoteLog.info("[SSHConnection] Deploying server... (retry: \(isRetry))")
            let path = try await deployer.ensureServerDeployed(host: host, onProgress: onProgress)
            self.remoteBinaryPath = path
            RemoteLog.info("[SSHConnection] Server deployed at \(path)")

            // 2. Establish connection
            RemoteLog.info("[SSHConnection] Establishing connection...")
            onProgress?("Connecting to")
            try await establishConnection()
            state = .connected
            startHealthCheck()
            reconnectAttempts = 0
            RemoteLog.info("[SSHConnection] Connected to \(host)")
        } catch {
            RemoteLog.info("[SSHConnection] Connection failed: \(error)")
            state = .disconnected
            throw error
        }
    }

    func establishConnection() async throws {
        RemoteLog.info("[SSHConnection] establishConnection() starting")
        guard let remoteBinaryPath = remoteBinaryPath else {
            RemoteLog.info("[SSHConnection] ERROR: No remote binary path")
            throw SSHConnectionError.serverNotResponding(host: host)
        }

        // Apply overall connection timeout (30 seconds for SSH + handshake)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.establishConnectionInternal(remoteBinaryPath: remoteBinaryPath)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                throw SSHConnectionError.helperStartupTimeout(host: self.host, stderr: "")
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
                self.process?.terminateIfRunning()
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
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            host,
            "\(remoteBinaryPath) proxy --reconnect"
        ]
        process.arguments = args
        RemoteLog.info("[SSHConnection] SSH command: ssh \(args.joined(separator: " "))")

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
                    RemoteLog.info("[SSHConnection] stderr: \(text)")
                }
            }
        }

        RemoteLog.info("[SSHConnection] Starting SSH process...")
        try process.run()
        RemoteLog.info("[SSHConnection] SSH process started, PID: \(process.processIdentifier)")

        // Brief wait to catch immediate SSH failures
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Check if process exited immediately (SSH error)
        if !process.isRunning {
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw parseSSHStderr(stderrCollector.getString(), host: host)
        }

        // Wait for sync marker - discard any shell initialization output (.bashrc, etc.)
        RemoteLog.info("[SSHConnection] Waiting for sync marker...")
        try await waitForSyncMarker(
            stdout: outPipe.fileHandleForReading,
            process: process,
            stderrCollector: stderrCollector,
            errPipe: errPipe)
        RemoteLog.info("[SSHConnection] Sync marker received, starting protocol")

        // Start reading loop
        startReading()
        RemoteLog.info("[SSHConnection] Reading loop started")

        // Handshake with specific timeout
        RemoteLog.info("[SSHConnection] Sending Hello handshake...")
        let hello = HelloPayload(clientVersion: AppVersion.current, protocolVersion: 1)

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

        RemoteLog.info("[SSHConnection] Got Hello response, decoding...")
        let response = try JSONDecoder().decode(RPCMessage<HelloResponsePayload>.self, from: responseData)

        guard response.payload.accepted else {
            RemoteLog.info("[SSHConnection] Handshake rejected!")
            throw SSHConnectionError.serverNotResponding(host: host)
        }
        RemoteLog.info("[SSHConnection] Handshake accepted!")
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
                RemoteLog.info("[SSHConnection] Sync marker timeout. Buffer: \(preview)")
                errPipe.fileHandleForReading.readabilityHandler = nil
                throw SSHConnectionError.helperStartupTimeout(host: host, stderr: stderrCollector.getString())
            }

            if !process.isRunning {
                errPipe.fileHandleForReading.readabilityHandler = nil
                throw parseSSHStderr(stderrCollector.getString(), host: host)
            }

            let result = await accumulator.getResult()
            if result.found {
                if !result.discarded.isEmpty {
                    let discarded = String(data: result.discarded, encoding: .utf8) ?? "<binary>"
                    RemoteLog.info("[SSHConnection] Discarded shell output: \(discarded.prefix(200))")
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

    public func send(
        type: String,
        payload: some Codable,
        timeout: TimeInterval = 10,
        disconnectOnTimeout: Bool = true
    ) async throws -> Data {
        #if canImport(os)
        sshLog.info("send() type=\(type)")
        #endif
        if state != .connected && state != .connecting {
            #if canImport(os)
            sshLog.error("send() rejected: state=\(String(describing: self.state))")
            #endif
            throw SSHConnectionError.serverNotResponding(host: host)
        }

        let id = nextRequestId
        nextRequestId += 1

        let data = try RPCStreamHandler.encode(id: id, type: type, payload: payload)

        guard let stdin = stdinPipe?.fileHandleForWriting else {
            #if canImport(os)
            sshLog.error("send() id=\(id): no stdin pipe")
            #endif
            throw SSHConnectionError.unexpectedDisconnect
        }

        // Serialize writes on a dedicated queue so concurrent send() calls
        // (possible via actor reentrancy) don't interleave on the pipe.
        #if canImport(os)
        sshLog.info("send() id=\(id): writing \(data.count) bytes to stdin...")
        #endif
        let stdinHandle = stdin
        let writeData = data
        let writeQueue = stdinWriteQueue
        let writeError: Error? = await withCheckedContinuation { continuation in
            writeQueue.async {
                do {
                    try stdinHandle.write(contentsOf: writeData)
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: error)
                }
            }
        }

        if let writeError {
            #if canImport(os)
            sshLog.error("send() id=\(id): stdin write failed — \(writeError.localizedDescription, privacy: .public)")
            #endif
            handleDisconnect()
            throw SSHConnectionError.unexpectedDisconnect
        }

        #if canImport(os)
        sshLog.info("send() id=\(id): written, waiting for response (timeout=\(timeout)s)")
        #endif

        // Wait for response with timeout - poll-based to ensure timeout works
        let deadline = Date().addingTimeInterval(timeout)
        registerPendingRequest(id: id)

        while Date() < deadline {
            if Task.isCancelled {
                pendingRequestIds.remove(id)
                completedResponses.removeValue(forKey: id)
                throw CancellationError()
            }

            if let response = completedResponses.removeValue(forKey: id) {
                #if canImport(os)
                sshLog.info("send() id=\(id): got response")
                #endif
                return response
            }

            if state != .connected && state != .connecting {
                pendingRequestIds.remove(id)
                throw SSHConnectionError.unexpectedDisconnect
            }

            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Timeout - connection is stale; force reconnect so it recovers
        #if canImport(os)
        sshLog.error("send() id=\(id): timeout after \(timeout)s — forcing reconnect")
        #endif
        pendingRequestIds.remove(id)
        completedResponses.removeValue(forKey: id)
        if disconnectOnTimeout {
            handleDisconnect()
        }
        throw SSHConnectionError.operationTimeout(operation: type)
    }

    var pendingRequestIds: Set<Int> = []
    var completedResponses: [Int: Data] = [:]

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
            RemoteLog.info("[SSHConnection] ERROR: No stdout pipe for reading")
            return
        }

        stdout.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData

            if data.isEmpty {
                RemoteLog.info("[SSHConnection] EOF on stdout, disconnecting")
                handle.readabilityHandler = nil
                Task { await self.handleDisconnect() }
                return
            }

            RemoteLog.info("[SSHConnection] Received \(data.count) bytes from stdout")
            Task { await self.processIncomingData(data) }
        }
    }

    private func processIncomingData(_ data: Data) {
        let messages = streamHandler.receive(data: data)
        RemoteLog.info("[SSHConnection] Parsed \(messages.count) messages from incoming data")
        for msgData in messages {
            if let header = try? JSONDecoder().decode(RPCHeader.self, from: msgData) {
                RemoteLog.info("[SSHConnection] Message: type=\(header.type), id=\(header.id?.description ?? "nil")")
                if let id = header.id {
                    if pendingRequestIds.contains(id) {
                        RemoteLog.info("[SSHConnection] Completing request id=\(id)")
                        completeRequest(id: id, data: msgData)
                    } else {
                        RemoteLog.info("[SSHConnection] WARNING: No pending request for id=\(id)")
                    }
                } else {
                    RemoteLog.info("[SSHConnection] Push event received")
                    eventContinuation?.yield(msgData)
                }
            } else {
                RemoteLog.info("[SSHConnection] ERROR: Failed to decode message header")
            }
        }
    }

    /// Finish both async stream continuations so consumers' for-await loops exit cleanly.
    func finishContinuations() {
        eventContinuation?.finish()
        eventContinuation = nil
        stateContinuation?.finish()
        stateContinuation = nil
    }

    deinit {
        eventContinuation?.finish()
        stateContinuation?.finish()
    }
}
// Extensions are in SSHConnectionExtensions.swift
