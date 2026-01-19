import XCTest
@testable import RedmarginLib

final class RemoteProtocolTests: XCTestCase {
    
    func testRPCMessageEncode() throws {
        let payload = ReadFilePayload(path: "/test.md")
        let data = try RPCStreamHandler.encode(id: 1, type: RPCMessageType.readFile.rawValue, payload: payload)
        
        // Check length prefix (4 bytes)
        let length = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(Int(length), data.count - 4)
        
        // Check JSON content
        let json = data.dropFirst(4)
        let message = try JSONDecoder().decode(RPCMessage<ReadFilePayload>.self, from: json)
        XCTAssertEqual(message.id, 1)
        XCTAssertEqual(message.type, "ReadFile")
        XCTAssertEqual(message.payload.path, "/test.md")
    }
    
    func testRPCStreamHandler() throws {
        let handler = RPCStreamHandler()
        
        // Create two messages
        let msg1 = try RPCStreamHandler.encode(id: 1, type: "Test", payload: "Message 1")
        let msg2 = try RPCStreamHandler.encode(id: 2, type: "Test", payload: "Message 2")
        
        // Send them in one chunk
        var combined = msg1
        combined.append(msg2)
        
        let results = handler.receive(data: combined)
        XCTAssertEqual(results.count, 2)
        
        let decoded1 = try JSONDecoder().decode(RPCMessage<String>.self, from: results[0])
        XCTAssertEqual(decoded1.payload, "Message 1")
        
        let decoded2 = try JSONDecoder().decode(RPCMessage<String>.self, from: results[1])
        XCTAssertEqual(decoded2.payload, "Message 2")
    }
    
    func testPartialDataHandling() throws {
        let handler = RPCStreamHandler()
        let data = try RPCStreamHandler.encode(id: 1, type: "Test", payload: "Full Message")
        
        // Send first half
        let splitIndex = data.count / 2
        let firstHalf = data.prefix(splitIndex)
        let secondHalf = data.dropFirst(splitIndex)
        
        let result1 = handler.receive(data: firstHalf)
        XCTAssertTrue(result1.isEmpty)
        
        let result2 = handler.receive(data: secondHalf)
        XCTAssertEqual(result2.count, 1)
        
        let decoded = try JSONDecoder().decode(RPCMessage<String>.self, from: result2[0])
        XCTAssertEqual(decoded.payload, "Full Message")
    }
}
