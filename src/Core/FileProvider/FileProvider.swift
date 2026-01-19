import Foundation

public typealias WatchToken = UUID

public protocol FileProvider {
    func readFile(at path: String) async throws -> String
    func writeFile(at path: String, content: String) async throws
    
    /// Starts watching a file for changes.
    /// Returns a token that must be used to stop watching.
    func watchFile(at path: String, onChange: @escaping () -> Void) -> WatchToken
    
    /// Stops watching a file or git repo using the provided token.
    func unwatch(_ token: WatchToken)
    
    func detectGitRepo(for path: String) async throws -> String?
    func gitDiff(for path: String, repoRoot: String) async throws -> GitChangeResult
    
    func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) -> WatchToken
}
