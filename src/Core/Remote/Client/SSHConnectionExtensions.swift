import Foundation
#if canImport(os)
import os.log
let sshLog = Logger(subsystem: "com.redmargin", category: "SSHConnection")
#endif

// MARK: - Connection Lifecycle

extension SSHConnection {
    func handleDisconnect() {
        // Guard against cascade: if already reconnecting/disconnected, skip.
        // Multiple concurrent send() failures can all call this in quick succession.
        guard state == .connected || state == .connecting else {
            #if canImport(os)
            sshLog.info(
                "handleDisconnect() skipped (already \(String(describing: self.state), privacy: .public))"
            )
            #endif
            return
        }
        #if canImport(os)
        sshLog.info("handleDisconnect() state=\(String(describing: self.state), privacy: .public)")
        #endif
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

        // Finish async streams so consumers exit their for-await loops
        finishContinuations()

        if !isIntentionallyDisconnected {
            state = .reconnecting
            reconnectTask?.cancel()
            reconnectTask = nil
            scheduleReconnect()
        } else {
            #if canImport(os)
            sshLog.info("handleDisconnect() intentional, not reconnecting")
            #endif
            state = .disconnected
        }
    }

    /// Periodically checks if the SSH process is still alive.
    /// Catches cases where SSH exited (e.g. ServerAliveInterval timeout killed it)
    /// but the readabilityHandler EOF didn't fire.
    func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                guard !Task.isCancelled, state == .connected else { continue }
                if process?.isRunning != true {
                    #if canImport(os)
                    sshLog.error("Health check: SSH process is dead, triggering reconnect")
                    #endif
                    handleDisconnect()
                }
            }
        }
    }

    func scheduleReconnect() {
        reconnectTask = Task {
            let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
            #if canImport(os)
            sshLog.info("scheduleReconnect() attempt=\(self.reconnectAttempts) delay=\(delay)s")
            #endif
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled, !isIntentionallyDisconnected else {
                #if canImport(os)
                sshLog.info("scheduleReconnect() cancelled or intentionally disconnected")
                #endif
                return
            }

            reconnectAttempts += 1
            state = .connecting
            do {
                try await establishConnection()
                state = .connected
                startHealthCheck()
                reconnectAttempts = 0
                #if canImport(os)
                sshLog.info("Reconnected successfully!")
                #endif
                NotificationCenter.default.post(
                    name: .sshConnectionReconnected,
                    object: self.host
                )
            } catch {
                guard !Task.isCancelled else { return }
                state = .reconnecting
                #if canImport(os)
                sshLog.error("Reconnection failed: \(error.localizedDescription, privacy: .public)")
                #endif
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

        // Finish async streams so consumers exit their for-await loops
        finishContinuations()

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
