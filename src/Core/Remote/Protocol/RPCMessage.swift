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
}

public class RPCStreamHandler {
    private var buffer = Data()
    
    public init() {}
    
    /// Appends data to the buffer and extracts any complete messages.
    /// Returns an array of Data, where each item is the JSON payload of a message.
    public func receive(data: Data) -> [Data] {
        buffer.append(data)
        var messages = [Data]()
        
        while true {
            // Need at least 4 bytes for length
            guard buffer.count >= 4 else { break }
            
            let length = buffer.withUnsafeBytes { ptr in
                ptr.load(as: UInt32.self).bigEndian
            }
            
            let totalLength = 4 + Int(length)
            
            guard buffer.count >= totalLength else { break }
            
            // Extract message JSON
            let messageData = buffer.subdata(in: 4..<totalLength)
            messages.append(messageData)
            
            // Advance buffer
            buffer.removeSubrange(0..<totalLength)
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
