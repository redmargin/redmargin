import Foundation

/// Helper for loading test fixture files
enum FixtureLoader {
    /// Loads a fixture file from the Tests/Fixtures directory
    /// - Parameter path: Relative path within Fixtures (e.g., "diff-samples/addition.diff")
    /// - Returns: Contents of the fixture file
    /// - Throws: If the file cannot be found or read
    static func load(_ path: String) throws -> String {
        // In Swift Package tests, Bundle.module provides access to resources
        // But for Xcode projects, we need to find the fixtures relative to the test file
        let fixturesURL = findFixturesDirectory()
        let fileURL = fixturesURL.appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FixtureError.notFound(path)
        }

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func findFixturesDirectory() -> URL {
        // Walk up from current file to find Tests/Fixtures
        // This works in Xcode test environments
        var url = URL(fileURLWithPath: #file)
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            let fixturesURL = url.appendingPathComponent("Fixtures")
            if FileManager.default.fileExists(atPath: fixturesURL.path) {
                return fixturesURL
            }
        }

        // Fallback: try relative to current working directory
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures")
    }
}

enum FixtureError: Error, LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Fixture not found: \(path)"
        }
    }
}
