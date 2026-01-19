import Foundation
import RedmarginCore

class RPCHandler {
    let fileOperations = FileOperations()
    private let gitOperations = GitOperations()
    
    func handle(_ data: Data) async -> Data? {
        // 1. Decode Header
        guard let header = try? JSONDecoder().decode(RPCHeader.self, from: data) else {
            print("Failed to decode RPC header")
            return nil
        }
        
        guard let type = RPCMessageType(rawValue: header.type) else {
            print("Unknown RPC message type: \(header.type)")
            return nil
        }
        
        do {
            switch type {
            case .hello:
                return try await handleHello(data)
            case .readFile:
                return try await handleReadFile(data)
            case .writeFile:
                return try await handleWriteFile(data)
            case .watchFile:
                return try await handleWatchFile(data)
            case .unwatchFile:
                return try await handleUnwatchFile(data)
            case .gitDetectRepo:
                return try await handleGitDetectRepo(data)
            case .gitDiff:
                return try await handleGitDiff(data)
            case .watchGitRepo:
                return try await handleWatchGitRepo(data)
            default:
                print("Unhandled message type: \(type)")
                return nil
            }
        } catch {
            print("Error handling message \(type): \(error)")
            return nil
        }
    }
    
    private func handleHello(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<HelloPayload>.self, from: data)
        let responsePayload = HelloResponsePayload(
            serverVersion: "1.0.0",
            protocolVersion: 1,
            accepted: true
        )
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.helloResponse.rawValue,
            payload: responsePayload
        )
    }
    
    private func handleReadFile(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<ReadFilePayload>.self, from: data)
        let responsePayload = await fileOperations.readFile(path: msg.payload.path)
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.readFileResponse.rawValue,
            payload: responsePayload
        )
    }
    
    private func handleWriteFile(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<WriteFilePayload>.self, from: data)
        let responsePayload = await fileOperations.writeFile(path: msg.payload.path, content: msg.payload.content)
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.writeFileResponse.rawValue,
            payload: responsePayload
        )
    }
    
    private func handleWatchFile(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<WatchFilePayload>.self, from: data)
        let token = await fileOperations.watchFile(path: msg.payload.path)
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.watchFileResponse.rawValue,
            payload: WatchFileResponsePayload(token: token)
        )
    }
    
    private func handleUnwatchFile(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<UnwatchFilePayload>.self, from: data)
        let success = await fileOperations.unwatchFile(token: msg.payload.token)
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.unwatchFileResponse.rawValue,
            payload: UnwatchFileResponsePayload(success: success)
        )
    }
    
    private func handleGitDetectRepo(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<GitDetectRepoPayload>.self, from: data)
        let repoRoot = await gitOperations.detectRepo(path: msg.payload.path)
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.gitDetectRepoResponse.rawValue,
            payload: GitDetectRepoResponsePayload(repoRoot: repoRoot)
        )
    }
    
    private func handleGitDiff(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<GitDiffPayload>.self, from: data)
        let responsePayload = await gitOperations.diff(path: msg.payload.path, repoRoot: msg.payload.repoRoot)
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.gitDiffResponse.rawValue,
            payload: responsePayload
        )
    }
    
    private func handleWatchGitRepo(_ data: Data) async throws -> Data {
        let msg = try JSONDecoder().decode(RPCMessage<WatchGitRepoPayload>.self, from: data)
        let token = await gitOperations.watchRepo(repoRoot: msg.payload.repoRoot)
        return try RPCStreamHandler.encode(
            id: msg.id,
            type: RPCMessageType.watchGitRepoResponse.rawValue,
            payload: WatchGitRepoResponsePayload(token: token)
        )
    }
}
