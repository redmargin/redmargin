import XCTest
@testable import RedmarginCore

final class ServerDeployerTests: XCTestCase {
    func testLocalBinaryNameSupportsIntelMacRemotes() {
        XCTAssertEqual(
            ServerDeployer.localBinaryName(osName: "Darwin", arch: "x86_64"),
            "redmargin-server-x86_64-darwin"
        )
    }

    func testLocalBinaryNameSupportsAppleSiliconMacRemotes() {
        XCTAssertEqual(
            ServerDeployer.localBinaryName(osName: "Darwin", arch: "arm64"),
            "redmargin-server-aarch64-darwin"
        )
    }

    func testLocalBinaryNameSupportsLinuxX86Remotes() {
        XCTAssertEqual(
            ServerDeployer.localBinaryName(osName: "Linux", arch: "x86_64"),
            "redmargin-server-x86_64-linux"
        )
    }

    func testLocalBinaryNameRejectsUnknownPlatforms() {
        XCTAssertNil(ServerDeployer.localBinaryName(osName: "SunOS", arch: "x86_64"))
        XCTAssertNil(ServerDeployer.localBinaryName(osName: "Linux", arch: "riscv64"))
    }

    // MARK: - Upload atomicity

    /// The binary is uploaded to a dot-prefixed temp path and only then renamed, so
    /// an upload cut short by the timeout cannot leave a truncated binary where the
    /// connect path execs it.
    func testUploadTargetIsATempPathDistinctFromTheCanonicalPath() {
        let temp = ServerDeployer.remoteTempPath(version: "1.2.3")
        let canonical = ServerDeployer.remoteBinaryPath(version: "1.2.3")

        XCTAssertNotEqual(temp, canonical)
        XCTAssertTrue(temp.hasSuffix(".tmp"), "The partial upload must be distinguishable")
        XCTAssertTrue(
            temp.contains("/.redmargin-server-"),
            "The partial upload is dot-prefixed so it never matches the cleanup glob"
        )
    }

    /// A failed chmod must fail the deploy rather than install a non-executable
    /// binary, so the two steps are chained with `&&`, and the move is atomic.
    func testInstallChainsChmodBeforeAnAtomicMove() {
        let install = ServerDeployer.installCommand(version: "1.2.3")

        XCTAssertTrue(install.hasPrefix("chmod +x "), "chmod runs first")
        XCTAssertTrue(install.contains(" && mv -f "), "A failed chmod aborts before the move")
        XCTAssertTrue(install.hasSuffix(ServerDeployer.remoteBinaryPath(version: "1.2.3")))
        XCTAssertFalse(install.contains("||"), "The install must not swallow a failure")
    }

    // MARK: - Version scoping

    /// Cleanup must delete other versions' binaries and nothing else. The running
    /// daemon's socket, its pid file, and an in-flight temp upload all have to
    /// survive it, as does the version being deployed.
    func testCleanupTargetsOnlyOtherVersionBinaries() {
        let cleanup = ServerDeployer.cleanupCommand(version: "1.2.3")

        XCTAssertTrue(cleanup.contains("-name 'redmargin-server-*'"), "Scoped to version binaries")
        XCTAssertTrue(cleanup.contains("! -name 'redmargin-server-1.2.3'"), "The current version is kept")
        XCTAssertTrue(cleanup.contains("-type f"), "Directories are never deleted")
        XCTAssertFalse(cleanup.contains("rpc.sock"))
        XCTAssertFalse(cleanup.contains("daemon.pid"))
        XCTAssertFalse(cleanup.contains("rm -rf"), "Cleanup never removes the shared directory")
    }

    /// The temp upload is dot-prefixed precisely so the cleanup glob cannot match it
    /// while a concurrent deploy is still writing it.
    func testCleanupGlobDoesNotMatchTheTempUpload() {
        let tempFileName = (ServerDeployer.remoteTempPath(version: "1.2.3") as NSString).lastPathComponent
        XCTAssertFalse(tempFileName.hasPrefix("redmargin-server-"), "Temp upload would match the cleanup glob")
        XCTAssertTrue(tempFileName.hasPrefix(".redmargin-server-"))
    }

    /// Killing or removing must never take down another version's live session on
    /// the same host.
    func testKillAndRemoveAreScopedToTheCurrentVersion() {
        let kill = ServerDeployer.killCommand(version: "1.2.3")
        XCTAssertTrue(kill.contains("edmargin-server-1.2.3"), "Scoped to this version")
        XCTAssertFalse(kill.contains("pkill -f redmargin-server "), "A bare pkill kills every version")

        let remove = ServerDeployer.removeCommand(version: "1.2.3")
        XCTAssertTrue(remove.contains(ServerDeployer.remoteBinaryPath(version: "1.2.3")))
        XCTAssertTrue(remove.contains(ServerDeployer.remoteTempPath(version: "1.2.3")), "The temp upload is cleaned")
        XCTAssertFalse(remove.contains("rm -rf"), "Removal never wipes the shared directory")
    }

    /// `pkill -f` matches whole command lines, including the remote shell running
    /// the pkill. An unbracketed pattern makes that shell match itself, so it is
    /// killed and anything after the pkill never runs.
    func testKillPatternCannotMatchTheShellRunningIt() {
        let kill = ServerDeployer.killCommand(version: "1.2.3")

        XCTAssertTrue(kill.contains("'[r]edmargin-server-1.2.3'"), "The pattern must be bracketed")
        XCTAssertFalse(
            kill.contains("-f redmargin-server-1.2.3"),
            "An unbracketed pattern matches the shell running it"
        )
    }

    /// And the removal must not share a command line with a pkill, because its own
    /// paths contain the process pattern and would match that shell.
    func testRemoveCommandDoesNotShareACommandLineWithAKill() {
        let remove = ServerDeployer.removeCommand(version: "1.2.3")

        XCTAssertFalse(
            remove.contains("pkill"),
            "The rm paths contain the process pattern; a pkill here would kill the shell before the rm"
        )
        XCTAssertTrue(remove.hasPrefix("rm -f "))
    }

    // MARK: - Timeouts

    /// Every SSH call is bounded. `cleanupOldVersions` is awaited before a deploy
    /// returns, so an unbounded call there would hang a completed deploy forever.
    func testEverySSHCallIsBoundedAndNonInteractive() {
        XCTAssertEqual(ServerDeployer.sshOptions, ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"])
        XCTAssertGreaterThan(ServerDeployer.sshTimeout, 0)
        XCTAssertGreaterThan(ServerDeployer.scpTimeout, ServerDeployer.sshTimeout, "Uploads need a longer budget")
    }
}
