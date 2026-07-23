import Foundation
import RedmarginCore

enum RemoteWorkspaceProbe: Equatable {
    case unreachable
    case reachable(RecentWorkspaceGitState)
}

/// ssh probes in batch mode, using the user's ssh config aliases exactly like
/// the app's connections. One round trip per remote folder answers both
/// "is the host up" and "what git state is that folder in".
enum RemoteWorkspaceProber {
    /// Plain reachability, for hosts that only carry file entries.
    static func isHostReachable(_ host: String) async -> Bool {
        do {
            let result = try await ProcessRunner.run(
                executable: "ssh",
                arguments: sshArguments(host: host, command: "true"),
                timeout: 8
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    /// Reachability plus git branch/dirty count for a remote folder. The
    /// remote command always exits 0 once the host answered, so a non-zero
    /// exit means the host itself is unreachable.
    static func probeFolder(host: String, path: String) async -> RemoteWorkspaceProbe {
        let quotedPath = AppDelegate.shellArgPreservingTilde(path)
        let script = "cd \(quotedPath) 2>/dev/null || { echo NODIR; exit 0; }; "
            + "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || { echo NOREPO; exit 0; }; "
            + "count=$(git status --porcelain -uall 2>/dev/null | wc -l); "
            + "printf 'REPO %s %s\\n' \"$branch\" \"$count\""
        do {
            let result = try await ProcessRunner.run(
                executable: "ssh",
                arguments: sshArguments(host: host, command: script),
                timeout: 10
            )
            return parse(exitCode: result.exitCode, output: result.stdout)
        } catch {
            return .unreachable
        }
    }

    static func parse(exitCode: Int32, output: String) -> RemoteWorkspaceProbe {
        guard exitCode == 0 else { return .unreachable }
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("REPO ") else {
            return .reachable(.notARepository)
        }
        let parts = line.split(separator: " ")
        // "REPO <branch> <count>"; git refnames cannot contain spaces.
        guard parts.count == 3, let count = Int(parts[2]) else {
            return .reachable(.notARepository)
        }
        return .reachable(.repo(GitWorkspaceSummary(branch: String(parts[1]), changedCount: count)))
    }

    private static func sshArguments(host: String, command: String) -> [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", host, command]
    }
}
