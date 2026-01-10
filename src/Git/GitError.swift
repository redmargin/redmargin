import Foundation

/// Errors that can occur during Git operations
enum GitError: Error, LocalizedError {
    /// Git executable was not found on the system
    case gitNotFound

    /// Permission denied when accessing file or directory
    case permissionDenied(String)

    /// An unexpected error occurred
    case unexpectedError(String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git is not installed or not found in PATH"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .unexpectedError(let message):
            return "Git error: \(message)"
        }
    }
}
