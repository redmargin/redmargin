import Foundation

public actor ServerDeployer {
    private let version = "0.77.1" // Match current app version
    private let sshTimeout: TimeInterval = 15 // seconds
    private let scpTimeout: TimeInterval = 60 // seconds for upload

    public init() {}

    /// SSH options for non-interactive mode
    private var sshOptions: [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
    }

    public func ensureServerDeployed(
        host: String,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        // 1. Detect remote OS and architecture
        onProgress?("Checking")
        let (osName, arch) = try await detectRemotePlatform(host: host)
        let remoteBinaryPath = "~/.redmargin-server/redmargin-server-\(version)"

        // 2. Check if already deployed
        let checkResult = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, "test -x \(remoteBinaryPath)"],
            timeout: sshTimeout
        )
        if checkResult.exitCode == 0 {
            print("[ServerDeployer] Server already deployed at \(remoteBinaryPath)")
            return remoteBinaryPath
        }

        // 3. Find local binary for OS and architecture
        guard let localBinaryURL = findLocalBinary(osName: osName, arch: arch) else {
            throw ServerDeployerError.unsupportedArchitecture("\(osName) \(arch)")
        }

        print("[ServerDeployer] Deploying \(localBinaryURL.lastPathComponent) to \(host)...")
        onProgress?("Deploying to")

        // 4. Create directory and upload
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, "mkdir -p ~/.redmargin-server"],
            timeout: sshTimeout
        )

        let scpResult = try await ProcessRunner.run(
            executable: "scp",
            arguments: ["-o", "BatchMode=yes"] + [localBinaryURL.path, "\(host):\(remoteBinaryPath)"],
            timeout: scpTimeout
        )
        if scpResult.exitCode != 0 {
            throw ServerDeployerError.uploadFailed(scpResult.stderr)
        }

        // 5. Set executable permissions
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, "chmod +x \(remoteBinaryPath)"],
            timeout: sshTimeout
        )

        // 6. Kill old daemon/proxy processes and clean up old binaries
        await killOldProcesses(host: host)
        await cleanupOldVersions(host: host)

        return remoteBinaryPath
    }

    private func detectRemotePlatform(host: String) async throws -> (osName: String, arch: String) {
        let result = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, "uname -sm"],
            timeout: sshTimeout
        )
        if result.exitCode != 0 {
            throw ServerDeployerError.connectionFailed(result.stderr)
        }
        let uname = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = uname.split(separator: " ")
        guard parts.count >= 2 else {
            throw ServerDeployerError.unsupportedArchitecture(uname)
        }
        return (String(parts[0]), String(parts[1]))
    }

    private func killOldProcesses(host: String) async {
        // Kill any running daemon/proxy processes so they restart with new binary
        let killCmd = "pkill -f redmargin-server 2>/dev/null || true"
        _ = try? await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, killCmd],
            timeout: sshTimeout
        )
        print("[ServerDeployer] Killed old server processes on \(host)")
    }

    private func findLocalBinary(osName: String, arch: String) -> URL? {
        let platform: String
        switch osName.lowercased() {
        case "darwin":
            platform = "darwin"
        case "linux":
            platform = "linux"
        default:
            return nil
        }

        // Normalize architecture names
        let normalizedArch: String
        switch arch {
        case "x86_64":
            normalizedArch = "x86_64"
        case "aarch64", "arm64":
            normalizedArch = "aarch64"
        default:
            return nil
        }

        let binaryName = "redmargin-server-\(normalizedArch)-\(platform)"

        // Look in Bundle Resources/Servers
        if let url = Bundle.main.url(forResource: binaryName, withExtension: nil, subdirectory: "Servers") {
            return url
        }

        // Fallback for development/testing (look in project root resources/servers)
        let devPath = "resources/servers/\(binaryName)"
        let devURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(devPath)
        if FileManager.default.fileExists(atPath: devURL.path) {
            return devURL
        }

        return nil
    }

    private func cleanupOldVersions(host: String) async {
        // Remove old version binaries (keep only current version)
        let cleanupCmd = """
            find ~/.redmargin-server -name 'redmargin-server-*' \
            ! -name 'redmargin-server-\(version)' -type f -delete 2>/dev/null || true
            """
        _ = try? await ProcessRunner.run(executable: "ssh", arguments: [host, cleanupCmd])
        print("[ServerDeployer] Cleaned up old versions")
    }

    /// Remove the deployed server binary to force re-deployment
    public func removeDeployedServer(host: String) async {
        // Kill any running daemon/proxy processes first
        let killCmd = "pkill -f redmargin-server 2>/dev/null || true"
        _ = try? await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, killCmd],
            timeout: sshTimeout
        )

        // Remove the server directory
        let removeCmd = "rm -rf ~/.redmargin-server"
        _ = try? await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, removeCmd],
            timeout: sshTimeout
        )
        print("[ServerDeployer] Killed processes and removed server on \(host)")
    }
}

public enum ServerDeployerError: Error, LocalizedError {
    case unsupportedArchitecture(String)
    case uploadFailed(String)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture(let arch):
            return "Remote architecture \(arch) is not supported."
        case .uploadFailed(let error):
            return "Failed to upload server binary: \(error)"
        case .connectionFailed(let error):
            if error.contains("Permission denied") || error.contains("publickey") {
                return "SSH authentication failed. Configure SSH keys for this host."
            }
            return "SSH connection failed: \(error)"
        }
    }
}
