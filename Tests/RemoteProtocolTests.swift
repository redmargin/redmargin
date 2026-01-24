import XCTest
@testable import RedmarginLib
import RedmarginCore

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

    func testRPCMessageDecodeInvalid() throws {
        // 1. Invalid JSON inside valid frame
        var data = Data()
        let invalidJson = Data("{ invalid }".utf8)
        let length = UInt32(invalidJson.count).bigEndian
        data.append(withUnsafeBytes(of: length) { Data($0) })
        data.append(invalidJson)

        let handler = RPCStreamHandler()
        let messages = handler.receive(data: data)
        XCTAssertEqual(messages.count, 1)

        // Decoding should fail
        XCTAssertThrowsError(try JSONDecoder().decode(RPCMessage<String>.self, from: messages[0]))
    }

    func testHelloHandshake() throws {
        let payload = HelloPayload(clientVersion: "1.0.0", protocolVersion: 1)
        let data = try RPCStreamHandler.encode(id: 1, type: RPCMessageType.hello.rawValue, payload: payload)

        let handler = RPCStreamHandler()
        let messages = handler.receive(data: data)
        XCTAssertEqual(messages.count, 1)

        let message = try JSONDecoder().decode(RPCMessage<HelloPayload>.self, from: messages[0])
        XCTAssertEqual(message.type, "Hello")
        XCTAssertEqual(message.payload.clientVersion, "1.0.0")
        XCTAssertEqual(message.payload.protocolVersion, 1)
    }

    func testAllMessageTypesRoundtrip() throws {
        // Verify we can encode/decode a complex payload like GitChangedPayload
        let payload = GitChangedPayload(repoRoot: "/tmp/repo")
        let data = try RPCStreamHandler.encode(id: nil, type: "GitChanged", payload: payload)

        let handler = RPCStreamHandler()
        let messages = handler.receive(data: data)
        XCTAssertEqual(messages.count, 1)

        let message = try JSONDecoder().decode(RPCMessage<GitChangedPayload>.self, from: messages[0])
        XCTAssertEqual(message.type, "GitChanged")
        XCTAssertEqual(message.payload.repoRoot, "/tmp/repo")
    }
}
