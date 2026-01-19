import Foundation

public actor RemoteFileProvider: FileProvider {
    private let connection: SSHConnection
    private var watchers: [WatchToken: WatchCallback] = [:]
    private var remoteTokens: [WatchToken: String] = [:] // Local Token -> Remote Token String
    
    private struct WatchCallback {
        let path: String
        let callback: () -> Void
    }
    
    public init(connection: SSHConnection) {
        self.connection = connection
        
        // Start listening for push events
        Task { [weak self] in
            for await eventData in connection.events {
                guard let self = self else { break }
                await self.handlePushEvent(eventData)
            }
        }
    }
    
    public func readFile(at path: String) async throws -> String {
        let payload = ReadFilePayload(path: path)
        let data = try await connection.send(type: RPCMessageType.readFile.rawValue, payload: payload)
        let response = try JSONDecoder().decode(RPCMessage<ReadFileResponsePayload>.self, from: data)
        
        if let error = response.payload.error {
            throw NSError(domain: "RemoteFileProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        return response.payload.content ?? ""
    }
    
    public func writeFile(at path: String, content: String) async throws {
        let payload = WriteFilePayload(path: path, content: content)
        let data = try await connection.send(type: RPCMessageType.writeFile.rawValue, payload: payload)
        let response = try JSONDecoder().decode(RPCMessage<WriteFileResponsePayload>.self, from: data)
        
        if let error = response.payload.error {
            throw NSError(domain: "RemoteFileProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: error])
        }
    }
    
    public func watchFile(at path: String, onChange: @escaping () -> Void) async -> WatchToken {
        let token = WatchToken()
        watchers[token] = WatchCallback(path: path, callback: onChange)
        
        let payload = WatchFilePayload(path: path)
        do {
            let data = try await connection.send(type: RPCMessageType.watchFile.rawValue, payload: payload)
            let response = try JSONDecoder().decode(RPCMessage<WatchFileResponsePayload>.self, from: data)
            remoteTokens[token] = response.payload.token
        } catch {
            print("[RemoteFileProvider] Failed to start remote watch for \(path): \(error)")
        }
        
        return token
    }
    
    public func unwatch(_ token: WatchToken) async {
        let remoteToken = remoteTokens.removeValue(forKey: token)
        watchers.removeValue(forKey: token)
        
        if let remoteToken = remoteToken {
            let payload = UnwatchFilePayload(token: remoteToken)
            _ = try? await connection.send(type: RPCMessageType.unwatchFile.rawValue, payload: payload)
        }
    }
    
    public func detectGitRepo(for path: String) async throws -> String? {
        let payload = GitDetectRepoPayload(path: path)
        let data = try await connection.send(type: RPCMessageType.gitDetectRepo.rawValue, payload: payload)
        let response = try JSONDecoder().decode(RPCMessage<GitDetectRepoResponsePayload>.self, from: data)
        return response.payload.repoRoot
    }
    
    public func gitDiff(for path: String, repoRoot: String) async throws -> GitChangeResult {
        let payload = GitDiffPayload(path: path, repoRoot: repoRoot)
        let data = try await connection.send(type: RPCMessageType.gitDiff.rawValue, payload: payload)
        let response = try JSONDecoder().decode(RPCMessage<GitDiffResponsePayload>.self, from: data)
        
        if let error = response.payload.error {
            throw NSError(domain: "RemoteFileProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: error])
        }
        
        return response.payload.diff ?? .empty
    }
    
    public func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken {
        let token = WatchToken()
        watchers[token] = WatchCallback(path: repoRoot, callback: onChange)
        
        let payload = WatchGitRepoPayload(repoRoot: repoRoot)
        do {
            let data = try await connection.send(type: RPCMessageType.watchGitRepo.rawValue, payload: payload)
            let response = try JSONDecoder().decode(RPCMessage<WatchGitRepoResponsePayload>.self, from: data)
            remoteTokens[token] = response.payload.token
        } catch {
            print("[RemoteFileProvider] Failed to start remote git watch for \(repoRoot): \(error)")
        }
        
        return token
    }
    
    private func handlePushEvent(_ data: Data) {
        if let msg = try? JSONDecoder().decode(RPCMessage<FileChangedPayload>.self, from: data),
           msg.type == RPCMessageType.fileChanged.rawValue {
            
            let callbacks = watchers.values.filter { $0.path == msg.payload.path }
            for item in callbacks {
                item.callback()
            }
        } else if let msg = try? JSONDecoder().decode(RPCMessage<GitChangedPayload>.self, from: data),
                  msg.type == RPCMessageType.gitChanged.rawValue {
            
            let callbacks = watchers.values.filter { $0.path == msg.payload.repoRoot }
            for item in callbacks {
                item.callback()
            }
        }
    }
}