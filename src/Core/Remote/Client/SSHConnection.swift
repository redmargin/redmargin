import Foundation

public enum SSHConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

public actor SSHConnection {
    private let host: String
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    
    private let streamHandler = RPCStreamHandler()
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
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
    
    public func connect() async throws {
        if state == .connected { return }
        state = .connecting
        isIntentionallyDisconnected = false
        
        do {
            // 1. Ensure server is deployed
            let path = try await deployer.ensureServerDeployed(host: host)
            self.remoteBinaryPath = path
            
            // 2. Establish connection
            try await establishConnection()
            state = .connected
            reconnectAttempts = 0
            print("[SSHConnection] Connected to \(host)")
        } catch {
            state = .disconnected
            throw error
        }
    }
    
    private func establishConnection() async throws {
        guard let remoteBinaryPath = remoteBinaryPath else {
            throw RPCError.incompleteData
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        process.arguments = [
            "-q",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=~/.ssh/redmargin-%r@%h:%p",
            host,
            "\(remoteBinaryPath) proxy --reconnect"
        ]
        
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
        
        try process.run()
        
        // Start reading loop
        startReading()
        
        // Handshake
        let hello = HelloPayload(clientVersion: "1.0.0", protocolVersion: 1)
        
        // Send handshake with timeout
        // (Simplified for now, send relies on pipe)
        let responseData = try await send(type: RPCMessageType.hello.rawValue, payload: hello)
        let response = try JSONDecoder().decode(RPCMessage<HelloResponsePayload>.self, from: responseData)
        
        guard response.payload.accepted else {
            throw RPCError.incompleteData
        }
    }
    
    public func send(type: String, payload: some Codable) async throws -> Data {
        if state != .connected && state != .connecting {
            throw RPCError.incompleteData // Todo: NotConnected
        }
        
        let id = nextRequestId
        nextRequestId += 1
        
        let data = try RPCStreamHandler.encode(id: id, type: type, payload: payload)
        
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw RPCError.incompleteData
        }
        
        try stdin.write(contentsOf: data)
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }
    
    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else { return }
        
        stdout.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { await self.handleDisconnect() }
                return
            }
            
            Task { await self.processIncomingData(data) }
        }
    }
    
    private func processIncomingData(_ data: Data) {
        let messages = streamHandler.receive(data: data)
        for msgData in messages {
            if let header = try? JSONDecoder().decode(RPCHeader.self, from: msgData) {
                if let id = header.id, let continuation = pendingRequests.removeValue(forKey: id) {
                    continuation.resume(returning: msgData)
                } else if header.id == nil {
                    eventContinuation?.yield(msgData)
                }
            }
        }
    }
    
    private func handleDisconnect() {
        // Fail pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: RPCError.incompleteData)
        }
        pendingRequests.removeAll()
        
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
        
        // Cancel pending
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: RPCError.incompleteData)
        }
        pendingRequests.removeAll()
    }
}