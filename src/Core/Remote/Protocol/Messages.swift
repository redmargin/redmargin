import Foundation

public enum RPCMessageType: String, Codable {
    case hello = "Hello"
    case helloResponse = "HelloResponse"
    case listDirectory = "ListDirectory"
    case listDirectoryResponse = "ListDirectoryResponse"
    case readFile = "ReadFile"
    case readFileResponse = "ReadFileResponse"
    case readAsset = "ReadAsset"
    case readAssetResponse = "ReadAssetResponse"
    case writeFile = "WriteFile"
    case writeFileResponse = "WriteFileResponse"
    case watchFile = "WatchFile"
    case watchFileResponse = "WatchFileResponse"
    case unwatchFile = "UnwatchFile"
    case unwatchFileResponse = "UnwatchFileResponse"
    case fileChanged = "FileChanged"
    case gitDetectRepo = "GitDetectRepo"
    case gitDetectRepoResponse = "GitDetectRepoResponse"
    case gitDiff = "GitDiff"
    case gitDiffResponse = "GitDiffResponse"
    case watchGitRepo = "WatchGitRepo"
    case watchGitRepoResponse = "WatchGitRepoResponse"
    case gitChanged = "GitChanged"
    case findMarkdownFiles = "FindMarkdownFiles"
    case findMarkdownFilesResponse = "FindMarkdownFilesResponse"
    case watchDirectory = "WatchDirectory"
    case watchDirectoryResponse = "WatchDirectoryResponse"
    case unwatchDirectory = "UnwatchDirectory"
    case unwatchDirectoryResponse = "UnwatchDirectoryResponse"
    case directoryChanged = "DirectoryChanged"
}

// MARK: - Handshake

public struct HelloPayload: Codable {
    public let clientVersion: String
    public let protocolVersion: Int

    public init(clientVersion: String, protocolVersion: Int) {
        self.clientVersion = clientVersion
        self.protocolVersion = protocolVersion
    }
}

public struct HelloResponsePayload: Codable {
    public let serverVersion: String
    public let protocolVersion: Int
    public let accepted: Bool

    public init(serverVersion: String, protocolVersion: Int, accepted: Bool) {
        self.serverVersion = serverVersion
        self.protocolVersion = protocolVersion
        self.accepted = accepted
    }
}

// MARK: - Directory Listing

public struct ListDirectoryPayload: Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct DirectoryEntry: Codable, Identifiable {
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?

    public var id: String { name }

    public init(name: String, isDirectory: Bool, size: Int64? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }
}

public struct ListDirectoryResponsePayload: Codable {
    public let entries: [DirectoryEntry]?
    public let error: String?

    public init(entries: [DirectoryEntry]?, error: String?) {
        self.entries = entries
        self.error = error
    }
}

// MARK: - File Operations

public struct ReadFilePayload: Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct ReadFileResponsePayload: Codable {
    public let content: String?
    public let error: String?
    public let errorCode: String?

    public init(content: String?, error: String?, errorCode: String? = nil) {
        self.content = content
        self.error = error
        self.errorCode = errorCode
    }
}

public enum FileErrorCode: String {
    case fileNotFound = "FILE_NOT_FOUND"
    case permissionDenied = "PERMISSION_DENIED"
}

public struct WriteFilePayload: Codable {
    public let path: String
    public let content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public struct WriteFileResponsePayload: Codable {
    public let error: String?

    public init(error: String?) {
        self.error = error
    }
}

// MARK: - Asset Reading (binary files)

public struct ReadAssetPayload: Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct ReadAssetResponsePayload: Codable {
    public let data: String?      // base64 encoded binary
    public let mimeType: String?
    public let error: String?

    public init(data: String?, mimeType: String?, error: String?) {
        self.data = data
        self.mimeType = mimeType
        self.error = error
    }
}

// MARK: - File Watching

public struct WatchFilePayload: Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct WatchFileResponsePayload: Codable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct UnwatchFilePayload: Codable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct UnwatchFileResponsePayload: Codable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct FileChangedPayload: Codable {
    public let path: String
    public let changeType: String // "modified", "deleted", "renamed"

    public init(path: String, changeType: String) {
        self.path = path
        self.changeType = changeType
    }
}

// MARK: - Git Operations

public struct GitDetectRepoPayload: Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct GitDetectRepoResponsePayload: Codable {
    public let repoRoot: String?

    public init(repoRoot: String?) {
        self.repoRoot = repoRoot
    }
}

public struct GitDiffPayload: Codable {
    public let path: String
    public let repoRoot: String

    public init(path: String, repoRoot: String) {
        self.path = path
        self.repoRoot = repoRoot
    }
}

public struct GitDiffResponsePayload: Codable {
    public let diff: GitChangeResult?
    public let error: String?

    public init(diff: GitChangeResult?, error: String?) {
        self.diff = diff
        self.error = error
    }
}

public struct WatchGitRepoPayload: Codable {
    public let repoRoot: String

    public init(repoRoot: String) {
        self.repoRoot = repoRoot
    }
}

public struct WatchGitRepoResponsePayload: Codable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct GitChangedPayload: Codable {
    public let repoRoot: String

    public init(repoRoot: String) {
        self.repoRoot = repoRoot
    }
}

// MARK: - Directory Watching

public struct WatchDirectoryPayload: Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct WatchDirectoryResponsePayload: Codable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct UnwatchDirectoryPayload: Codable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct UnwatchDirectoryResponsePayload: Codable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct DirectoryChangedPayload: Codable {
    public let path: String
    public let files: [String]

    public init(path: String, files: [String]) {
        self.path = path
        self.files = files
    }
}

// MARK: - Find Markdown Files

public struct FindMarkdownFilesPayload: Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct FindMarkdownFilesResponsePayload: Codable {
    public let files: [String]?
    public let error: String?

    public init(files: [String]?, error: String?) {
        self.files = files
        self.error = error
    }
}
