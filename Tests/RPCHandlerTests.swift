import XCTest
@testable import RedmarginCore
@testable import redmargin_server

/// `RPCHandler.handle` is the helper's entry point for every frame a client sends. It
/// answers with `nil` rather than throwing, so the daemon keeps the connection open.
/// These cover the three ways it can decide it has nothing to answer with.
final class RPCHandlerTests: XCTestCase {

    private func frame(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    /// Bytes that are not a JSON object at all.
    func testGarbageBytesYieldNoResponse() async throws {
        let response = await RPCHandler().handle(Data([0x00, 0x01, 0x02, 0xFF]))
        XCTAssertNil(response, "An undecodable header must not produce a response")
    }

    /// Valid JSON, but nothing that decodes as an RPC header.
    func testJSONWithoutAHeaderYieldsNoResponse() async throws {
        let data = try frame(["not": "a header"])
        let response = await RPCHandler().handle(data)
        XCTAssertNil(response, "JSON without a type must not produce a response")
    }

    /// A well-formed header naming a message type the helper does not implement.
    func testUnknownMessageTypeYieldsNoResponse() async throws {
        let data = try frame(["id": 1, "type": "DefinitelyNotARealMessageType"])
        let response = await RPCHandler().handle(data)
        XCTAssertNil(response, "An unrecognised message type must not produce a response")
    }

    /// A known type whose payload is missing, so routing throws while decoding it.
    func testKnownTypeWithAMissingPayloadYieldsNoResponse() async throws {
        let data = try frame(["id": 2, "type": RPCMessageType.readFile.rawValue])
        let response = await RPCHandler().handle(data)
        XCTAssertNil(response, "A payload that fails to decode must not produce a response")
    }

    /// The handler survives a bad frame and still answers the next good one, which is the
    /// reason it returns nil instead of throwing.
    func testHandlerStillAnswersAfterABadFrame() async throws {
        let handler = RPCHandler()

        let ignored = await handler.handle(Data([0xFF, 0xFE]))
        XCTAssertNil(ignored)

        let hello = try frame([
            "id": 3,
            "type": RPCMessageType.hello.rawValue,
            "payload": ["clientVersion": "test", "protocolVersion": 1]
        ])
        let response = await handler.handle(hello)
        XCTAssertNotNil(response, "A good frame after a bad one must still be answered")
    }
}
