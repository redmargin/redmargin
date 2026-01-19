import Foundation
import RedmarginLib

actor GitOperations {
    
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
        // TODO: Implement repo watching
        return UUID().uuidString
    }
}
