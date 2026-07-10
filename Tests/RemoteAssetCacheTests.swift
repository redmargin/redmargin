import XCTest
import WebKit
@testable import RedmarginLib

/// Stands in for the WebKit-owned scheme task so the handler can be driven
/// directly, without a web view deciding when to request what.
private final class StubSchemeTask: NSObject, WKURLSchemeTask, @unchecked Sendable {
    let request: URLRequest
    private let lock = NSLock()
    private var data = Data()
    private var finished = false
    private var failure: Error?

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func didReceive(_ response: URLResponse) {}

    func didReceive(_ data: Data) {
        lock.lock()
        self.data.append(data)
        lock.unlock()
    }

    func didFinish() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    func didFailWithError(_ error: Error) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    var receivedText: String? {
        lock.lock()
        defer { lock.unlock() }
        return finished ? String(data: data, encoding: .utf8) : nil
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished || failure != nil
    }
}

final class RemoteAssetCacheTests: XCTestCase {
    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        webView = WKWebView(frame: .zero)
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    /// Runs one request through the handler and waits for it to settle.
    @discardableResult
    private func fetch(_ handler: RemoteAssetSchemeHandler, _ urlString: String) throws -> StubSchemeTask {
        let task = StubSchemeTask(url: url(urlString))
        handler.webView(webView, start: task)

        let deadline = Date().addingTimeInterval(5)
        while !task.isFinished && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(task.isFinished, "Request for \(urlString) never completed")
        return task
    }

    /// A counting fetcher whose payload changes on every call, so a stale cache
    /// entry is visible in the bytes the handler hands back.
    private func makeVersioningFetcher() -> (fetch: (String) async throws -> (Data, String)?, count: () -> Int) {
        let counter = Counter()
        let fetcher: (String) async throws -> (Data, String)? = { _ in
            let version = counter.increment()
            return (Data("version-\(version)".utf8), "text/plain")
        }
        return (fetcher, counter.value)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
        func value() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    /// The same URL is served from cache: the whole point of the cache.
    func testRepeatedRequestForTheSameURLIsServedFromCache() throws {
        let (fetcher, count) = makeVersioningFetcher()
        let handler = RemoteAssetSchemeHandler(fetchAsset: fetcher)

        let first = try fetch(handler, "redmargin-remote:///img.png?_cb=1")
        let second = try fetch(handler, "redmargin-remote:///img.png?_cb=1")

        XCTAssertEqual(first.receivedText, "version-1")
        XCTAssertEqual(second.receivedText, "version-1")
        XCTAssertEqual(count(), 1, "A cached asset was fetched twice")
    }

    /// The regression: refreshing a document re-requests each image with a new
    /// cache-bust token. Keying on path alone kept serving the old bytes, so a
    /// changed image never appeared until the app restarted.
    func testRefreshedImageIsNotServedFromTheStaleCacheEntry() throws {
        let (fetcher, count) = makeVersioningFetcher()
        let handler = RemoteAssetSchemeHandler(fetchAsset: fetcher)

        let before = try fetch(handler, "redmargin-remote:///img.png?_cb=1")
        let afterRefresh = try fetch(handler, "redmargin-remote:///img.png?_cb=2")

        XCTAssertEqual(before.receivedText, "version-1")
        XCTAssertEqual(afterRefresh.receivedText, "version-2", "A refreshed image returned stale bytes")
        XCTAssertEqual(count(), 2)
    }

    /// Once a path has been refreshed, the superseded generation is dropped rather
    /// than left to occupy the cache until it is evicted.
    func testSupersededGenerationIsEvicted() throws {
        let (fetcher, count) = makeVersioningFetcher()
        let handler = RemoteAssetSchemeHandler(fetchAsset: fetcher)

        try fetch(handler, "redmargin-remote:///img.png?_cb=1")
        try fetch(handler, "redmargin-remote:///img.png?_cb=2")
        // Asking for the old token again must re-fetch, not resurrect old bytes.
        let old = try fetch(handler, "redmargin-remote:///img.png?_cb=1")

        XCTAssertEqual(old.receivedText, "version-3")
        XCTAssertEqual(count(), 3)
    }

    /// Distinct paths remain independently cached.
    func testDifferentPathsAreCachedSeparately() throws {
        let (fetcher, count) = makeVersioningFetcher()
        let handler = RemoteAssetSchemeHandler(fetchAsset: fetcher)

        try fetch(handler, "redmargin-remote:///a.png?_cb=1")
        try fetch(handler, "redmargin-remote:///b.png?_cb=1")
        try fetch(handler, "redmargin-remote:///a.png?_cb=1")

        XCTAssertEqual(count(), 2, "Caching one path evicted another")
    }

    /// A request served from cache runs to completion without ever suspending, so
    /// nothing orders its completion after its registration. Registering under the
    /// same lock that cleanup takes makes the leak impossible by construction.
    ///
    /// This asserts that invariant across many concurrent requests. It does not
    /// reproduce the interleaving: the window between creating the task and
    /// recording it is a few instructions wide, and the task cannot win that race
    /// often enough to fail reliably. Treat it as a guard on the invariant, not as
    /// a demonstration of the original defect.
    func testCompletedTasksAreNotRetained() throws {
        let (fetcher, _) = makeVersioningFetcher()
        let handler = RemoteAssetSchemeHandler(fetchAsset: fetcher)

        // Prime the cache so every request below completes without suspending.
        try fetch(handler, "redmargin-remote:///img.png?_cb=1")

        let tasks = (0..<500).map { _ in StubSchemeTask(url: url("redmargin-remote:///img.png?_cb=1")) }
        for task in tasks {
            handler.webView(webView, start: task)
        }

        let deadline = Date().addingTimeInterval(10)
        while !tasks.allSatisfy({ $0.isFinished }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(tasks.allSatisfy(\.isFinished), "Requests never completed")

        // Give any trailing cleanup a moment to run.
        while handler.activeTaskCount != 0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(handler.activeTaskCount, 0, "Completed asset tasks were left retained")
    }
}
