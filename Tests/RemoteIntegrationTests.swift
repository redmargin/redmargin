import XCTest
@testable import RedmarginCore

final class RemoteIntegrationTests: XCTestCase {
    
    func testServerDeployer() async throws {
        let deployer = ServerDeployer()
        print("[Test] Testing deployment to devtest...")
        
        do {
            // First, delete any existing binary to force deployment
            _ = try await ProcessRunner.run(executable: "ssh", arguments: ["devtest", "rm -rf ~/.redmargin-server"])
            
            let remotePath = try await deployer.ensureServerDeployed(host: "devtest")
            XCTAssertTrue(remotePath.contains("redmargin-server"))
            print("[Test] Server deployed to \(remotePath)")
            
            // Verify it exists and is executable
            let check = try await ProcessRunner.run(executable: "ssh", arguments: ["devtest", "test -x \(remotePath)"])
            XCTAssertEqual(check.exitCode, 0)
        } catch {
            XCTFail("Deployment failed: \(error)")
        }
    }
    
    func testRemoteFileProvider() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()
        
        let provider = RemoteFileProvider(connection: connection)
        let tempPath = "/tmp/redmargin-provider-test.md"
        
        print("[Test] Testing RemoteFileProvider operations...")
        
        // 1. Write
        let content = "Hello from Provider"
        try await provider.writeFile(at: tempPath, content: content)
        
        // 2. Read
        let readContent = try await provider.readFile(at: tempPath)
        XCTAssertEqual(readContent, content)
        
        // 3. Watch
        let expectation = XCTestExpectation(description: "Watch callback")
        let token = await provider.watchFile(at: tempPath) {
            print("[Test] Watch callback triggered!")
            expectation.fulfill()
        }
        
        // Wait for watcher to register
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Trigger change
        try await provider.writeFile(at: tempPath, content: "Changed content")
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // 4. Unwatch
        await provider.unwatch(token)
        
        await connection.disconnect()
    }
    
    func testControlMasterReuse() async throws {
        let conn1 = SSHConnection(host: "devtest")
        let conn2 = SSHConnection(host: "devtest")
        
        print("[Test] Testing ControlMaster reuse (multiplexing)...")
        
        try await conn1.connect()
        print("[Test] Connection 1 established (Master created)")
        
        try await conn2.connect()
        print("[Test] Connection 2 established (Multiplexed)")
        
        await conn1.disconnect()
        await conn2.disconnect()
        print("[Test] Connections closed.")
    }
}