import Foundation

public actor ServerDeployer {
    private let version = "1.0.0" // Match current app version
    private let sshTimeout: TimeInterval = 15 // seconds
    private let scpTimeout: TimeInterval = 120 // seconds for upload (67MB binary)

    public init() {}

    /// SSH options for non-interactive mode
    private var sshOptions: [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
    }

    public func ensureServerDeployed(
        host: String,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        // 1. Single SSH call to detect platform, check binary, and get hash
        onProgress?("Checking")
        let remoteBinaryPath = "~/.redmargin-server/redmargin-server-\(version)"
        let combinedCmd = """
            uname -sm; \
            test -x \(remoteBinaryPath) && echo EXISTS || echo MISSING; \
            md5sum \(remoteBinaryPath) 2>/dev/null | cut -d' ' -f1 || echo NOHASH
            """
        let checkResult = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, combinedCmd],
            timeout: sshTimeout
        )
        if checkResult.exitCode != 0 {
            throw ServerDeployerError.connectionFailed(checkResult.stderr)
        }

        let lines = checkResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        guard lines.count >= 2 else {
            throw ServerDeployerError.connectionFailed("Unexpected output from remote check")
        }

        // Parse uname output
        let unameParts = lines[0].split(separator: " ")
        guard unameParts.count >= 2 else {
            throw ServerDeployerError.unsupportedArchitecture(lines[0])
        }
        let osName = String(unameParts[0])
        let arch = String(unameParts[1])

        // 2. Find local binary
        guard let localBinaryURL = findLocalBinary(osName: osName, arch: arch) else {
            throw ServerDeployerError.unsupportedArchitecture("\(osName) \(arch)")
        }

        // 3. Check deployment status from combined output
        let binaryExists = lines.count > 1 && lines[1] == "EXISTS"
        let remoteHash = lines.count > 2 ? lines[2] : "NOHASH"

        if binaryExists && remoteHash != "NOHASH" {
            let localHash = md5Hash(of: localBinaryURL)
            if localHash == remoteHash {
                print("[ServerDeployer] Server already deployed and up-to-date at \(remoteBinaryPath)")
                onProgress?("Connecting to")
                return remoteBinaryPath
            }
            print("[ServerDeployer] Hash mismatch: local=\(localHash ?? "nil") remote=\(remoteHash)")
        }

        print("[ServerDeployer] Deploying \(localBinaryURL.lastPathComponent) to \(host)...")

        // 4. Kill old daemon FIRST so we can overwrite the binary
        onProgress?("Stopping old server on")
        await killOldProcesses(host: host)

        // 5. Create directory and upload
        onProgress?("Uploading to")
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

        // 6. Set executable permissions
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, "chmod +x \(remoteBinaryPath)"],
            timeout: sshTimeout
        )

        // 7. Clean up old version binaries
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

    /// Check if local binary is newer than deployed binary by comparing MD5 hashes
    private func binaryNeedsUpdate(host: String, remotePath: String, localURL: URL) async -> Bool {
        // Get local file hash
        guard let localHash = md5Hash(of: localURL) else {
            print("[ServerDeployer] Could not hash local binary, will redeploy")
            return true
        }

        // Get remote file hash
        let hashCmd = "md5sum \(remotePath) 2>/dev/null | cut -d' ' -f1"
        guard let result = try? await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, hashCmd],
            timeout: sshTimeout
        ), result.exitCode == 0 else {
            print("[ServerDeployer] Could not get remote hash, will redeploy")
            return true
        }

        let remoteHash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsUpdate = localHash != remoteHash
        if needsUpdate {
            print("[ServerDeployer] Hash mismatch: local=\(localHash) remote=\(remoteHash)")
        }
        return needsUpdate
    }

    /// Calculate MD5 hash of a file using system md5 command
    private func md5Hash(of url: URL) -> String? {
        // Use md5 command on macOS (outputs "MD5 (file) = hash")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/md5")
        process.arguments = ["-q", url.path]  // -q for quiet (hash only)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let hash = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !hash.isEmpty else {
                return nil
            }
            return hash
        } catch {
            return nil
        }
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
