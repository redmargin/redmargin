import Foundation

public actor ServerDeployer {
    private var version: String { AppVersion.current }
    private let sshTimeout: TimeInterval = 15 // seconds
    private let scpTimeout: TimeInterval = 120 // seconds for upload (67MB binary)

    public init() {}

    /// SSH options for non-interactive mode. A 5s connect timeout fast-fails
    /// unreachable hosts during restore/warm without holding up other windows.
    private var sshOptions: [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]
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
            // Classify the SSH failure so the connect/restore/warm path sees a typed,
            // correctly (non-)retryable error: "no route"/"network unreachable" →
            // .hostUnreachable, "connection refused" → .connectionRefused, auth
            // failures → .authenticationFailed. ServerDeployerError stays for
            // architecture and upload failures only.
            throw parseSSHStderr(checkResult.stderr, host: host)
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
                RemoteLog.info("[ServerDeployer] Server already deployed and up-to-date at \(remoteBinaryPath)")
                onProgress?("Connecting to")
                return remoteBinaryPath
            }
            RemoteLog.info("[ServerDeployer] Hash mismatch: local=\(localHash ?? "nil") remote=\(remoteHash)")
        }

        RemoteLog.info("[ServerDeployer] Deploying \(localBinaryURL.lastPathComponent) to \(host)...")

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

        // Upload to a temp path, then chmod + atomically mv into place. Writing
        // straight to the canonical path meant an scp interrupted by the timeout
        // left a truncated binary exactly where establishConnection execs
        // `proxy --reconnect`; the mv makes the final path appear only once the
        // whole binary is present and executable.
        let tmpPath = "~/.redmargin-server/.redmargin-server-\(version).tmp"
        let scpResult = try await ProcessRunner.run(
            executable: "scp",
            arguments: ["-o", "BatchMode=yes"] + [localBinaryURL.path, "\(host):\(tmpPath)"],
            timeout: scpTimeout
        )
        if scpResult.exitCode != 0 {
            throw ServerDeployerError.uploadFailed(scpResult.stderr)
        }

        // 6. Set executable permissions and move into place atomically. A failed
        // chmod must fail the deploy, not ship a non-exec binary the connect path
        // then loops trying to exec.
        let installResult = try await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, "chmod +x \(tmpPath) && mv -f \(tmpPath) \(remoteBinaryPath)"],
            timeout: sshTimeout
        )
        if installResult.exitCode != 0 {
            throw ServerDeployerError.uploadFailed(installResult.stderr)
        }

        // 7. Clean up old version binaries
        await cleanupOldVersions(host: host)

        return remoteBinaryPath
    }

    private func killOldProcesses(host: String) async {
        // Kill only THIS version's daemon/proxy so we can overwrite its binary.
        // A bare `pkill -f redmargin-server` also kills every other version and
        // every other live session for this user on the host, dropping a
        // concurrent window mid-use; scoping to the versioned name avoids that.
        let killCmd = "pkill -f redmargin-server-\(version) 2>/dev/null || true"
        _ = try? await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, killCmd],
            timeout: sshTimeout
        )
        RemoteLog.info("[ServerDeployer] Killed old server processes on \(host)")
    }

    private func findLocalBinary(osName: String, arch: String) -> URL? {
        guard let binaryName = Self.localBinaryName(osName: osName, arch: arch) else {
            return nil
        }

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

    internal static func localBinaryName(osName: String, arch: String) -> String? {
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

        return "redmargin-server-\(normalizedArch)-\(platform)"
    }

    private func cleanupOldVersions(host: String) async {
        // Remove old version binaries (keep only current version). This is awaited
        // before ensureServerDeployed returns, so it must carry the same BatchMode
        // + timeout as every other SSH call; without them a stall here hangs a
        // fully-uploaded deploy indefinitely.
        let cleanupCmd = """
            find ~/.redmargin-server -name 'redmargin-server-*' \
            ! -name 'redmargin-server-\(version)' -type f -delete 2>/dev/null || true
            """
        _ = try? await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, cleanupCmd],
            timeout: sshTimeout
        )
        RemoteLog.info("[ServerDeployer] Cleaned up old versions")
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

    /// Remove this version's deployed server binary to force re-deployment.
    /// Scoped to the current version so a self-heal or forced restart does not
    /// kill other versions' daemons or `rm -rf` the shared directory out from
    /// under a concurrent session on the same host.
    public func removeDeployedServer(host: String) async {
        let binaryPath = "~/.redmargin-server/redmargin-server-\(version)"
        // Kill only this version's processes, then remove its binary (and any
        // stale temp upload). Other versions and their live sessions are left be.
        let cmd = """
            pkill -f redmargin-server-\(version) 2>/dev/null; \
            rm -f \(binaryPath) ~/.redmargin-server/.redmargin-server-\(version).tmp 2>/dev/null || true
            """
        _ = try? await ProcessRunner.run(
            executable: "ssh",
            arguments: sshOptions + [host, cmd],
            timeout: sshTimeout
        )
        RemoteLog.info("[ServerDeployer] Killed processes and removed server on \(host)")
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
