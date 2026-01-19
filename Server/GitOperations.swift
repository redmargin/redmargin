import Foundation
import RedmarginCore

actor GitOperations {
    private var eventHandler: ((Data) -> Void)?
    private var watchers: [String: GitWatcher] = [:]
    
    func setEventHandler(_ handler: @escaping (Data) -> Void) {
        self.eventHandler = handler
    }
    
    func detectRepo(path: String) async -> String? {
        let url = URL(fileURLWithPath: path)
        do {
            let root = try await GitRepoDetector.detectRepoRoot(forFile: url)
            return root?.path
        } catch {
            return nil
        }
    }
    
    func diff(path: String, repoRoot: String) async -> GitDiffResponsePayload {
        let fileURL = URL(fileURLWithPath: path)
        let rootURL = URL(fileURLWithPath: repoRoot)
        
        do {
            let changes = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: rootURL)
            return GitDiffResponsePayload(diff: changes, error: nil)
        } catch {
            return GitDiffResponsePayload(diff: nil, error: error.localizedDescription)
        }
    }
    
    func watchRepo(repoRoot: String) -> String {
        let token = UUID().uuidString
        
        let watcher = GitWatcher(repoRoot: repoRoot) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }
                print("[GitWatcher] Git changed: \(repoRoot)")
                
                let payload = GitChangedPayload(repoRoot: repoRoot)
                if let data = try? RPCStreamHandler.encode(id: nil, type: RPCMessageType.gitChanged.rawValue, payload: payload) {
                    await self.eventHandler?(data)
                }
            }
        }
        
        watchers[token] = watcher
        return token
    }
    
    func unwatchRepo(token: String) -> Bool {
        if let watcher = watchers.removeValue(forKey: token) {
            watcher.stop()
            return true
        }
        return false
    }
}