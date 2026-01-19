import Foundation

public actor ServerDeployer {
    private let version = "0.42.0" // Match current app version
    
    public init() {}
    
    public func ensureServerDeployed(host: String) async throws -> String {
        // 1. Detect remote architecture
        let archResult = try await ProcessRunner.run(executable: "ssh", arguments: [host, "uname -m"])
        let arch = archResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let remoteBinaryPath = "~/.redmargin-server/redmargin-server-\(version)"
        
        // 2. Check if already deployed
        let checkResult = try await ProcessRunner.run(executable: "ssh", arguments: [host, "test -x \(remoteBinaryPath)"])
        if checkResult.exitCode == 0 {
            print("[ServerDeployer] Server already deployed at \(remoteBinaryPath)")
            return remoteBinaryPath
        }
        
        // 3. Find local binary for architecture
        guard let localBinaryURL = findLocalBinary(for: arch) else {
            throw ServerDeployerError.unsupportedArchitecture(arch)
        }
        
        print("[ServerDeployer] Deploying \(localBinaryURL.lastPathComponent) to \(host)...")
        
        // 4. Create directory and upload
        _ = try await ProcessRunner.run(executable: "ssh", arguments: [host, "mkdir -p ~/.redmargin-server"])
        
        let scpResult = try await ProcessRunner.run(executable: "scp", arguments: [localBinaryURL.path, "\(host):\(remoteBinaryPath)"])
        if scpResult.exitCode != 0 {
            throw ServerDeployerError.uploadFailed(scpResult.stderr)
        }
        
        // 5. Set executable permissions
        _ = try await ProcessRunner.run(executable: "ssh", arguments: [host, "chmod +x \(remoteBinaryPath)"])
        
        return remoteBinaryPath
    }
    
    private func findLocalBinary(for arch: String) -> URL? {
        // Expected architectures: x86_64, aarch64, arm64
        let binaryName: String
        switch arch {
        case "x86_64":
            binaryName = "redmargin-server-x86_64-linux" // Assume Linux for now if x86_64
        case "aarch64", "arm64":
            binaryName = "redmargin-server-aarch64-linux"
        default:
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
}

public enum ServerDeployerError: Error, LocalizedError {
    case unsupportedArchitecture(String)
    case uploadFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture(let arch):
            return "Remote architecture \(arch) is not supported."
        case .uploadFailed(let error):
            return "Failed to upload server binary: \(error)"
        }
    }
}
