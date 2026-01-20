import Foundation

public actor ServerDeployer {
    private let version = "0.42.3" // Match current app version
    private let sshTimeout: TimeInterval = 15 // seconds
    private let scpTimeout: TimeInterval = 60 // seconds for upload

    public init() {}

    /// SSH options for non-interactive mode
    private var sshOptions: [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
    }

    public func ensureServerDeployed(host: String) async throws -> String {
        // 1. Detect remote OS and architecture
        let unameResult = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, "uname -sm"],
            timeout: sshTimeout
        )
        if unameResult.exitCode != 0 {
            throw ServerDeployerError.connectionFailed(unameResult.stderr)
        }
        let uname = unameResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = uname.split(separator: " ")
        guard parts.count >= 2 else {
            throw ServerDeployerError.unsupportedArchitecture(uname)
        }
        let os = String(parts[0]) // Darwin or Linux
        let arch = String(parts[1]) // x86_64, arm64, aarch64

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
        guard let localBinaryURL = findLocalBinary(os: os, arch: arch) else {
            throw ServerDeployerError.unsupportedArchitecture("\(os) \(arch)")
        }

        print("[ServerDeployer] Deploying \(localBinaryURL.lastPathComponent) to \(host)...")

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

        // 6. Clean up old versions
        await cleanupOldVersions(host: host)

        return remoteBinaryPath
    }

    private func findLocalBinary(os: String, arch: String) -> URL? {
        let platform: String
        switch os.lowercased() {
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
        let cleanupCmd = "find ~/.redmargin-server -name 'redmargin-server-*' ! -name 'redmargin-server-\(version)' -type f -delete 2>/dev/null || true"
        _ = try? await ProcessRunner.run(executable: "ssh", arguments: [host, cleanupCmd])
        print("[ServerDeployer] Cleaned up old versions")
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
