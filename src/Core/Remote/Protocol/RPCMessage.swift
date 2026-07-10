import Foundation

public struct RPCHeader: Codable {
    public let id: Int?
    public let type: String
}

public struct RPCMessage<T: Codable>: Codable {
    public let id: Int?
    public let type: String
    public let payload: T

    public init(id: Int?, type: String, payload: T) {
        self.id = id
        self.type = type
        self.payload = payload
    }
}

public enum RPCError: Error {
    case incompleteData
    case invalidEncoding
    case serverError(String)
}

public class RPCStreamHandler {
    private var buffer = Data()

    /// Upper bound on a single frame. No legitimate message approaches this; a
    /// larger declared length means the stream is corrupt or desynced, so buffering
    /// toward it would grow memory without bound (a trivial OOM from a bad prefix).
    static let maxFrameLength: UInt32 = 64 * 1024 * 1024 // 64 MB

    public init() {}

    /// Discards any buffered partial data (call on reconnect to avoid corrupted framing).
    public func reset() {
        buffer.removeAll()
    }

    /// Appends data to the buffer and extracts any complete messages.
    /// Returns an array of Data, where each item is the JSON payload of a message.
    public func receive(data: Data) -> [Data] {
        buffer.append(data)
        var messages = [Data]()

        while true {
            // Need at least 4 bytes for length
            guard buffer.count >= 4 else { break }

            // Read the big-endian length prefix byte-wise. A `load(as: UInt32)`
            // on the buffer's raw bytes can trap on a misaligned access after the
            // front has been trimmed (Data storage is not guaranteed 4-byte
            // aligned), particularly on aarch64.
            let base = buffer.startIndex
            let length = (UInt32(buffer[base]) << 24)
                | (UInt32(buffer[base + 1]) << 16)
                | (UInt32(buffer[base + 2]) << 8)
                | UInt32(buffer[base + 3])

            if length > Self.maxFrameLength {
                // Framing is corrupt: drop the buffer so we do not buffer toward
                // OOM or block a reader forever on bytes that will never arrive.
                // A reset stream (reconnect) resyncs cleanly.
                buffer.removeAll()
                break
            }

            let totalLength = 4 + Int(length)

            guard buffer.count >= totalLength else { break }

            // Extract message JSON
            let messageData = buffer.subdata(in: (base + 4)..<(base + totalLength))
            messages.append(messageData)

            // Advance buffer
            buffer.removeSubrange(base..<(base + totalLength))
        }

        return messages
    }

    /// Encodes a generic payload with a header into a length-prefixed Data packet.
    public static func encode<T: Codable>(id: Int?, type: String, payload: T) throws -> Data {
        let message = RPCMessage(id: id, type: type, payload: payload)
        let jsonData = try JSONEncoder().encode(message)

        var length = UInt32(jsonData.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(jsonData)
        return data
    }
}
