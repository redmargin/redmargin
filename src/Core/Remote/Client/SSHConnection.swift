import Foundation

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
    public let events: AsyncStream<Data>
    
    public init(host: String) {
        self.host = host
        var continuation: AsyncStream<Data>.Continuation?
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }
    
    public func connect() async throws {
        // TODO: Use ControlMaster
        // For now, direct connection
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        // Command: ssh host "~/.redmargin-server/redmargin-server-1.0.0 proxy --reconnect"
        // We'll assume the binary is there or we use a simplified command for now
        // Spec says: ssh host "~/.redmargin-server/redmargin-server-X.X.X proxy --reconnect"
        
        // For testing locally, we might want to run the server binary directly if host is "localhost"?
        // Or just assume ssh works.
        
        process.arguments = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=~/.ssh/redmargin-%r@%h:%p",
            host,
            "~/.redmargin-server/redmargin-server proxy --reconnect"
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
        let responseData = try await send(type: RPCMessageType.hello.rawValue, payload: hello)
        let response = try JSONDecoder().decode(RPCMessage<HelloResponsePayload>.self, from: responseData)
        
        guard response.payload.accepted else {
            throw RPCError.incompleteData // Todo: HandshakeError
        }
    }
    
    public func send(type: String, payload: some Codable) async throws -> Data {
        let id = nextRequestId
        nextRequestId += 1
        
        let data = try RPCStreamHandler.encode(id: id, type: type, payload: payload)
        
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw RPCError.incompleteData // Todo: ConnectionError
        }
        
        try stdin.write(contentsOf: data)
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }
    
    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else { return }
        
        // Read in background
        // Using FileHandle.readabilityHandler or a loop
        stdout.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if data.isEmpty {
                // EOF
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
            // Decode header to find ID
            if let header = try? JSONDecoder().decode(RPCHeader.self, from: msgData) {
                if let id = header.id, let continuation = pendingRequests.removeValue(forKey: id) {
                    continuation.resume(returning: msgData)
                } else if header.id == nil {
                    // Push event
                    eventContinuation?.yield(msgData)
                }
            }
        }
    }
    
    private func handleDisconnect() {
        // Fail all pending
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: RPCError.incompleteData) // Disconnected
        }
        pendingRequests.removeAll()
    }
    
    public func disconnect() {
        process?.terminate()
    }
}
