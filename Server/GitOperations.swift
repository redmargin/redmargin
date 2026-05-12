import Foundation
import RedmarginCore

actor GitOperations {
    private var eventHandler: ((Data) -> Void)?
    private var watchers: [String: GitWatcher] = [:]
    private var repoToToken: [String: String] = [:]  // repoRoot -> token (dedup)

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

    func status(path: String) async -> GitStatusResponsePayload {
        let url = URL(fileURLWithPath: path)
        let snapshot = await GitStatusProvider.shared.status(for: url)
        return GitStatusResponsePayload(snapshot: snapshot, error: nil)
    }

    func watchRepo(repoRoot: String) -> String {
        // Remove existing watcher for this repo to prevent accumulation
        if let existingToken = repoToToken[repoRoot] {
            watchers[existingToken]?.stop()
            watchers.removeValue(forKey: existingToken)
            print("[GitOperations] Replaced existing watcher for \(repoRoot)")
        }

        let token = UUID().uuidString
        repoToToken[repoRoot] = token

        let watcher = GitWatcher(repoRoot: repoRoot) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }
                print("[GitWatcher] Git changed: \(repoRoot)")

                let payload = GitChangedPayload(repoRoot: repoRoot)
                let msgType = RPCMessageType.gitChanged.rawValue
                if let data = try? RPCStreamHandler.encode(id: nil, type: msgType, payload: payload) {
                    await self.eventHandler?(data)
                }
            }
        }

        watchers[token] = watcher
        return token
    }

    func unwatchRepo(token: String) -> Bool {
        if let watcher = watchers.removeValue(forKey: token) {
            // Find and remove the repoRoot -> token mapping
            if let entry = repoToToken.first(where: { $0.value == token }) {
                repoToToken.removeValue(forKey: entry.key)
            }
            watcher.stop()
            return true
        }
        return false
    }
}
