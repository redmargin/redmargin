import Foundation
import RedmarginCore

enum RemoteHostProber {
    /// ssh probe in batch mode; true when the host answers within the timeout.
    /// Uses the user's ssh config aliases exactly like the app's connections.
    static func isReachable(host: String) async -> Bool {
        do {
            let result = try await ProcessRunner.run(
                executable: "ssh",
                arguments: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", host, "true"],
                timeout: 8
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }
}
