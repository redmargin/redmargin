import XCTest
import AppKit
@testable import Redmargin
@testable import RedmarginCore

@MainActor
final class RemoteWindowPersistenceTests: WindowlessTestCase {
    private let key = "RedMargin.OpenRemoteLocations"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Regression: a remote window the user closed must not resurrect on the next
    /// launch. On-demand restore builds a window for every saved location, so at quit
    /// we persist exactly the windows still open — the previously-saved list is not
    /// merged back in (that merge re-added every closed window).
    func testClosedRemoteWindowIsNotResurrectedAtQuit() throws {
        let a = RemoteLocation(host: "host.example", path: "/a.md")
        let b = RemoteLocation(host: "host.example", path: "/b.md")
        let c = RemoteLocation(host: "host.example", path: "/c.md")

        // The previous session had A, B, and C open.
        UserDefaults.standard.set(try JSONEncoder().encode([a, b, c]), forKey: key)

        let app = NSApplication.shared
        let delegate = AppDelegate()

        // This session: the user closed C, so only A and B remain open.
        let window = NSWindow()
        delegate.remoteDocumentWindows[a] = window
        delegate.remoteDocumentWindows[b] = window

        _ = delegate.applicationShouldTerminate(app)

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: key))
        let saved = try JSONDecoder().decode([RemoteLocation].self, from: data)

        XCTAssertEqual(Set(saved), Set([a, b]), "Only windows still open should be persisted")
        XCTAssertFalse(saved.contains(c), "A window the user closed must not be re-added from the prior saved list")
    }

    /// With no remote windows open, the saved list is cleared entirely rather than
    /// retaining a stale set that would reopen windows the user closed.
    func testQuittingWithNoRemoteWindowsClearsSavedList() throws {
        let a = RemoteLocation(host: "host.example", path: "/a.md")
        UserDefaults.standard.set(try JSONEncoder().encode([a]), forKey: key)

        let app = NSApplication.shared
        let delegate = AppDelegate()
        // No remote windows open this session.

        _ = delegate.applicationShouldTerminate(app)

        XCTAssertNil(
            UserDefaults.standard.data(forKey: key),
            "Closing every remote window should leave nothing to restore"
        )
    }
}
