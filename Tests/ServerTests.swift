import XCTest
@testable import RedmarginCore

#if canImport(Darwin)
import Darwin
let testSystemClose = Darwin.close
let testSocketRead = Darwin.read
let testSocketWrite = Darwin.write
#elseif canImport(Glibc)
import Glibc
let testSystemClose = Glibc.close
let testSocketRead = Glibc.read
let testSocketWrite = Glibc.write
#endif

final class ServerTests: XCTestCase {
    var tempDir: URL!
    var serverProcess: Process?

    override func setUp() async throws {
        // Use /tmp directly to keep socket paths short (Unix socket limit is 104 chars)
        let shortId = UUID().uuidString.prefix(8)
        tempDir = URL(fileURLWithPath: "/tmp/rm-test-\(shortId)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let process = serverProcess, process.isRunning {
            await stopProcess(process)
        }
        serverProcess = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Test that the daemon creates socket and PID file, and responds to RPC
    func testDaemonStartStop() async throws {
        let pidFile = tempDir.appendingPathComponent("daemon.pid").path
        let socketPath = tempDir.appendingPathComponent("rpc.sock").path

        guard let serverPath = findServerBinary() else {
            XCTFail("Server binary not found. Build with ./resources/scripts/build.sh first.")
            return
        }

        let (process, stderrPipe) = try startDaemon(
            serverPath: serverPath,
            pidFile: pidFile,
            socketPath: socketPath
        )
        serverProcess = process
        try await Task.sleep(nanoseconds: 500_000_000)

        // Check if process is still running
        guard process.isRunning else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "no output"
            XCTFail("Daemon process exited prematurely. stderr: \(stderr)")
            return
        }

        // Verify PID file and socket
        XCTAssertTrue(FileManager.default.fileExists(atPath: pidFile), "PID file should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath), "Socket file should exist")

        let pidString = try String(contentsOfFile: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = Int32(pidString)
        XCTAssertNotNil(pid, "PID file should contain a valid process ID")
        XCTAssertEqual(pid, process.processIdentifier, "PID file should match process ID")

        // Connect and send Hello
        let clientFD = connectToSocket(socketPath)
        XCTAssertGreaterThanOrEqual(clientFD, 0, "Should connect to daemon socket")
        defer { if clientFD >= 0 { _ = testSystemClose(clientFD) } }

        let response = try await sendHelloAndGetResponse(clientFD: clientFD)
        XCTAssertEqual(response.type, RPCMessageType.helloResponse.rawValue)
        XCTAssertTrue(response.payload.accepted)
        XCTAssertEqual(response.payload.protocolVersion, 1)

        await stopProcess(process)
        XCTAssertFalse(process.isRunning, "Daemon should have stopped")
    }

    func testFileWatchPushEvent() async throws {
        let pidFile = tempDir.appendingPathComponent("daemon.pid").path
        let socketPath = tempDir.appendingPathComponent("rpc.sock").path
        let watchedFile = tempDir.appendingPathComponent("watched.md")
        try "# Before\n".write(to: watchedFile, atomically: false, encoding: .utf8)

        guard let serverPath = findServerBinary() else {
            XCTFail("Server binary not found. Build with ./resources/scripts/build.sh first.")
            return
        }

        let (process, stderrPipe) = try startDaemon(
            serverPath: serverPath,
            pidFile: pidFile,
            socketPath: socketPath
        )
        serverProcess = process
        try await Task.sleep(nanoseconds: 500_000_000)

        guard process.isRunning else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "no output"
            XCTFail("Daemon process exited prematurely. stderr: \(stderr)")
            return
        }

        let clientFD = connectToSocket(socketPath)
        XCTAssertGreaterThanOrEqual(clientFD, 0, "Should connect to daemon socket")
        defer { if clientFD >= 0 { _ = testSystemClose(clientFD) } }

        let helloResponse = try await sendHelloAndGetResponse(clientFD: clientFD)
        XCTAssertTrue(helloResponse.payload.accepted)

        _ = try await sendWatchFileRequest(clientFD: clientFD, path: watchedFile.path)
        try await Task.sleep(nanoseconds: 200_000_000)

        try "# After\n".write(to: watchedFile, atomically: false, encoding: .utf8)

        let sawFileChanged = try await pollForFileChangedEvent(
            clientFD: clientFD,
            expectedPath: watchedFile.path,
            timeout: 5.0
        )
        XCTAssertTrue(sawFileChanged, "Daemon should push FileChanged for watched file")
    }

    func testReadAndWriteExpandTildePaths() async throws {
        let pidFile = tempDir.appendingPathComponent("daemon.pid").path
        let socketPath = tempDir.appendingPathComponent("rpc.sock").path
        let homeTestDirName = ".redmargin-tilde-test-\(UUID().uuidString.prefix(8))"
        let homeTestDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(homeTestDirName)
        try FileManager.default.createDirectory(at: homeTestDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeTestDir) }

        let readableFile = homeTestDir.appendingPathComponent("read.md")
        try "# Read via tilde\n".write(to: readableFile, atomically: false, encoding: .utf8)

        guard let serverPath = findServerBinary() else {
            XCTFail("Server binary not found. Build with ./resources/scripts/build.sh first.")
            return
        }

        let (process, stderrPipe) = try startDaemon(
            serverPath: serverPath,
            pidFile: pidFile,
            socketPath: socketPath
        )
        serverProcess = process
        try await Task.sleep(nanoseconds: 500_000_000)

        guard process.isRunning else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "no output"
            XCTFail("Daemon process exited prematurely. stderr: \(stderr)")
            return
        }

        let clientFD = connectToSocket(socketPath)
        XCTAssertGreaterThanOrEqual(clientFD, 0, "Should connect to daemon socket")
        defer { if clientFD >= 0 { _ = testSystemClose(clientFD) } }

        let helloResponse = try await sendHelloAndGetResponse(clientFD: clientFD)
        XCTAssertTrue(helloResponse.payload.accepted)

        let readResponse: RPCMessage<ReadFileResponsePayload> = try await sendRequest(
            clientFD: clientFD,
            id: 2,
            type: RPCMessageType.readFile.rawValue,
            payload: ReadFilePayload(path: "~/\(homeTestDirName)/read.md")
        )
        XCTAssertNil(readResponse.payload.error)
        XCTAssertEqual(readResponse.payload.content, "# Read via tilde\n")

        let writeResponse: RPCMessage<WriteFileResponsePayload> = try await sendRequest(
            clientFD: clientFD,
            id: 3,
            type: RPCMessageType.writeFile.rawValue,
            payload: WriteFilePayload(
                path: "~/\(homeTestDirName)/written.md",
                content: "# Written via tilde\n"
            )
        )
        XCTAssertNil(writeResponse.payload.error)

        let writtenContent = try String(
            contentsOf: homeTestDir.appendingPathComponent("written.md"),
            encoding: .utf8
        )
        XCTAssertEqual(writtenContent, "# Written via tilde\n")
    }

    /// Test that daemon survives proxy disconnect
    func testDaemonSurvivesProxyDisconnect() async throws {
        let pidFile = tempDir.appendingPathComponent("daemon.pid").path
        let socketPath = tempDir.appendingPathComponent("rpc.sock").path

        guard let serverPath = findServerBinary() else {
            XCTFail("Server binary not found. Build with ./resources/scripts/build.sh first.")
            return
        }

        let (process, stderrPipe) = try startDaemon(
            serverPath: serverPath,
            pidFile: pidFile,
            socketPath: socketPath
        )
        serverProcess = process
        try await Task.sleep(nanoseconds: 500_000_000)

        guard process.isRunning else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "no output"
            XCTFail("Daemon process exited prematurely. stderr: \(stderr)")
            return
        }

        // First connection
        let client1 = connectToSocket(socketPath)
        XCTAssertGreaterThanOrEqual(client1, 0)
        _ = try await sendHelloAndGetResponse(clientFD: client1)
        _ = testSystemClose(client1)

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(process.isRunning, "Daemon should survive client disconnect")

        // Second connection should work
        let client2 = connectToSocket(socketPath)
        XCTAssertGreaterThanOrEqual(client2, 0, "Should be able to reconnect to daemon")
        let response = try await sendHelloAndGetResponse(clientFD: client2)
        XCTAssertTrue(response.payload.accepted)
        _ = testSystemClose(client2)

        await stopProcess(process)
    }

    // MARK: - Helpers

    /// Locates the built helper relative to this source file, so the tests run from any
    /// checkout rather than only from one developer's home directory.
    private func findServerBinary() -> String? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
        let buildDir = repoRoot.appendingPathComponent(".build")
        let possiblePaths = [
            buildDir.appendingPathComponent("debug/redmargin-server"),
            buildDir.appendingPathComponent("release/redmargin-server"),
            buildDir.appendingPathComponent("Build/Products/Debug/redmargin-server")
        ]
        return possiblePaths.map(\.path).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func startDaemon(
        serverPath: String,
        pidFile: String,
        socketPath: String
    ) throws -> (Process, Pipe) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = [
            "run",
            "--pid-file", pidFile,
            "--stdin-socket", socketPath,
            "--stdout-socket", "/dev/null",
            "--stderr-socket", "/dev/null"
        ]
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        return (process, stderrPipe)
    }

    private func stopProcess(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func connectToSocket(_ path: String) -> Int32 {
        #if os(Linux)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif

        let socketFD = socket(AF_UNIX, socketType, 0)
        guard socketFD >= 0 else { return -1 }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            path.withCString { pathPtr in
                strncpy(sunPath, pathPtr, 104)
            }
        }

        #if os(macOS)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(socketFD, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if result == 0 {
            return socketFD
        } else {
            _ = testSystemClose(socketFD)
            return -1
        }
    }

    private func sendHelloAndGetResponse(clientFD: Int32) async throws -> RPCMessage<HelloResponsePayload> {
        let helloPayload = HelloPayload(clientVersion: "1.0.0", protocolVersion: 1)
        let helloData = try RPCStreamHandler.encode(
            id: 1,
            type: RPCMessageType.hello.rawValue,
            payload: helloPayload
        )

        _ = helloData.withUnsafeBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return testSocketWrite(clientFD, baseAddress, helloData.count)
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let readResult = buffer.withUnsafeMutableBytes { ptr -> Int in
            testSocketRead(clientFD, ptr.baseAddress!, 4096)
        }

        guard readResult > 0 else {
            throw NSError(
                domain: "ServerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read response"]
            )
        }

        let responseData = Data(buffer.prefix(readResult))
        let streamHandler = RPCStreamHandler()
        let messages = streamHandler.receive(data: responseData)

        guard !messages.isEmpty else {
            throw NSError(
                domain: "ServerTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No messages received"]
            )
        }

        return try JSONDecoder().decode(RPCMessage<HelloResponsePayload>.self, from: messages[0])
    }

    private func sendWatchFileRequest(clientFD: Int32, path: String) async throws -> String {
        let watchPayload = WatchFilePayload(path: path)
        let watchData = try RPCStreamHandler.encode(
            id: 2,
            type: RPCMessageType.watchFile.rawValue,
            payload: watchPayload
        )

        _ = watchData.withUnsafeBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return testSocketWrite(clientFD, baseAddress, watchData.count)
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let readResult = buffer.withUnsafeMutableBytes { ptr -> Int in
            testSocketRead(clientFD, ptr.baseAddress!, 4096)
        }

        guard readResult > 0 else {
            throw NSError(
                domain: "ServerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read watch response"]
            )
        }

        let streamHandler = RPCStreamHandler()
        let messages = streamHandler.receive(data: Data(buffer.prefix(readResult)))
        let response = try JSONDecoder().decode(RPCMessage<WatchFileResponsePayload>.self, from: messages[0])

        return response.payload.token
    }

    private func sendRequest<Payload: Codable, Response: Codable>(
        clientFD: Int32,
        id: Int,
        type: String,
        payload: Payload
    ) async throws -> RPCMessage<Response> {
        let requestData = try RPCStreamHandler.encode(id: id, type: type, payload: payload)

        _ = requestData.withUnsafeBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return testSocketWrite(clientFD, baseAddress, requestData.count)
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let readResult = buffer.withUnsafeMutableBytes { ptr -> Int in
            testSocketRead(clientFD, ptr.baseAddress!, 4096)
        }

        guard readResult > 0 else {
            throw NSError(
                domain: "ServerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read response"]
            )
        }

        let streamHandler = RPCStreamHandler()
        let messages = streamHandler.receive(data: Data(buffer.prefix(readResult)))
        guard let responseData = messages.first else {
            throw NSError(
                domain: "ServerTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No messages received"]
            )
        }

        return try JSONDecoder().decode(RPCMessage<Response>.self, from: responseData)
    }

    private func pollForFileChangedEvent(
        clientFD: Int32,
        expectedPath: String,
        timeout: TimeInterval
    ) async throws -> Bool {
        var flags = fcntl(clientFD, F_GETFL)
        _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)
        defer {
            flags = fcntl(clientFD, F_GETFL)
            _ = fcntl(clientFD, F_SETFL, flags & ~O_NONBLOCK)
        }

        let startTime = Date()
        let streamHandler = RPCStreamHandler()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while Date().timeIntervalSince(startTime) < timeout {
            let readResult = buffer.withUnsafeMutableBytes { ptr -> Int in
                testSocketRead(clientFD, ptr.baseAddress!, 4096)
            }

            if readResult > 0 {
                let data = Data(buffer.prefix(readResult))
                let messages = streamHandler.receive(data: data)

                for msgData in messages where isFileChangedMessage(msgData, expectedPath: expectedPath) {
                    return true
                }
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        return false
    }

    private func isFileChangedMessage(_ msgData: Data, expectedPath: String) -> Bool {
        guard let header = try? JSONDecoder().decode(RPCHeader.self, from: msgData),
              header.type == RPCMessageType.fileChanged.rawValue,
              let fileChanged = try? JSONDecoder().decode(
                  RPCMessage<FileChangedPayload>.self,
                  from: msgData
              ) else {
            return false
        }
        return fileChanged.payload.path == expectedPath
    }
}
