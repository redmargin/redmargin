import XCTest
@testable import RedmarginCore

final class RemoteIntegrationTests: XCTestCase {
    
    func testConnectToDevTest() async throws {
        let connection = SSHConnection(host: "devtest")
        
        do {
            print("[Test] Connecting to devtest...")
            try await connection.connect()
            print("[Test] Handshake successful!")
            
            // Try to read a file from devtest
            // Let's assume /etc/hostname exists on any Linux
            let payload = ReadFilePayload(path: "/etc/hostname")
            let responseData = try await connection.send(type: RPCMessageType.readFile.rawValue, payload: payload)
            let response = try JSONDecoder().decode(RPCMessage<ReadFileResponsePayload>.self, from: responseData)
            
            XCTAssertNotNil(response.payload.content)
            print("[Test] Successfully read remote file content: \(response.payload.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "empty")")
            
            // Test File Watching
            print("[Test] Testing file watching...")
            let tempPath = "/tmp/redmargin-test-\(UUID().uuidString).md"
            
            // 1. Write file
            let writePayload = WriteFilePayload(path: tempPath, content: "Initial content")
            _ = try await connection.send(type: RPCMessageType.writeFile.rawValue, payload: writePayload)
            
            // 2. Watch file
            let watchPayload = WatchFilePayload(path: tempPath)
            _ = try await connection.send(type: RPCMessageType.watchFile.rawValue, payload: watchPayload)
            
            // 3. Setup listener for events
            let expectation = XCTestExpectation(description: "Receive FileChanged event")
            
            Task {
                for await eventData in connection.events {
                    if let message = try? JSONDecoder().decode(RPCMessage<FileChangedPayload>.self, from: eventData),
                       message.type == RPCMessageType.fileChanged.rawValue,
                       message.payload.path == tempPath {
                        print("[Test] Received FileChanged event for \(tempPath)")
                        expectation.fulfill()
                        break
                    }
                }
            }
            
            // 4. Modify file (wait a bit to ensure watcher is active)
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            let modifyPayload = WriteFilePayload(path: tempPath, content: "Modified content")
            _ = try await connection.send(type: RPCMessageType.writeFile.rawValue, payload: modifyPayload)
            
            // 5. Wait for event
            await fulfillment(of: [expectation], timeout: 5.0)
            
            await connection.disconnect()
        } catch {
            XCTFail("Failed to connect or communicate with devtest: \(error)")
        }
    }
}
