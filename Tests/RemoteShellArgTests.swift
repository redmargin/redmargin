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

    // MARK: - Command injection

    /// The result is interpolated into `test -d \(...)` and run by the remote shell.
    /// Nothing but a real tilde prefix may reach it unquoted.

    func testTildeWithMetacharactersAndNoSlashIsQuoted() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~;id"), "'~;id'")
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~$(id)"), "'~$(id)'")
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~`id`"), "'~`id`'")
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~ && rm -rf /"), "'~ && rm -rf /'")
    }

    /// The username segment is unquoted too, so it needs the same guard.
    func testTildeUserWithMetacharactersIsQuoted() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~a;id/notes"), "'~a;id/notes'")
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~$(id)/notes"), "'~$(id)/notes'")
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~gh ost/notes"), "'~gh ost/notes'")
    }

    /// A login name may hold these, and must still expand.
    func testOrdinaryLoginNamesStillExpand() {
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~git-user/notes"), "~git-user/'notes'")
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~user_1/notes"), "~user_1/'notes'")
        XCTAssertEqual(AppDelegate.shellArgPreservingTilde("~first.last/notes"), "~first.last/'notes'")
    }

    /// No metacharacter survives into the command line for any of these.
    func testNoMetacharacterEscapesQuoting() {
        for path in ["~;id", "~$(id)", "~`id`", "~a;id/x", "~|nc evil 1/x", "~\n id"] {
            let quoted = AppDelegate.shellArgPreservingTilde(path)
            let body = quoted.hasPrefix("'") ? String(quoted.dropFirst().dropLast()) : quoted
            for meta in [";", "$", "`", "|", "&", "\n"] where path.contains(meta) {
                XCTAssertTrue(
                    quoted.hasPrefix("'"),
                    "\(path) reached the shell unquoted as \(quoted)"
                )
                XCTAssertFalse(body.contains("'"), "Quoting of \(path) is not closed properly")
            }
        }
    }
}
