import XCTest
@testable import Redmargin

/// Covers `AppDelegate.shellArgPreservingTilde`, which quotes a remote path for a
/// shell command while leaving a leading `~`/`~user` segment unquoted so the remote
/// shell expands it. Regression guard for the "Folder does not exist" failure when
/// opening a recent remote folder whose path started with `~`.
final class RemoteShellArgTests: XCTestCase {
    func testTildeHomePathKeepsTildeUnquoted() {
        // Must produce ~/'engagement/' so the remote shell expands ~ to $HOME.
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~/engagement/"), "~/'engagement/'")
    }

    func testTildeUserPathKeepsPrefixUnquoted() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~ghost/engagement"), "~ghost/'engagement'")
    }

    func testBareTildeIsLeftAsIs() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~"), "~")
    }

    func testTildeSlashOnlyKeepsTrailingSlashUnquoted() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~/"), "~/")
    }

    func testAbsolutePathIsFullyQuoted() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("/Users/ghost/engagement/"), "'/Users/ghost/engagement/'")
    }

    func testPathWithSpacesIsQuoted() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~/my docs/notes"), "~/'my docs/notes'")
    }

    func testEmbeddedSingleQuoteIsEscaped() {
        // A literal single quote must be closed, escaped, and reopened.
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("/tmp/it's"), "'/tmp/it'\\''s'")
    }
}
