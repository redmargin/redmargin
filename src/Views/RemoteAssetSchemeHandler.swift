import Foundation
import WebKit

/// Wrapper for NSCache values (NSCache requires class types).
private class CachedAsset {
    let data: Data
    let mimeType: String
    let cost: Int

    init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
        self.cost = data.count
    }
}

public class RemoteAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "redmargin-remote"

    /// Identifies a cached asset. Refreshing a document re-requests each image
    /// with a new cache-bust token in the query, so a key of path alone would
    /// keep serving the bytes the refresh was meant to replace.
    private struct CacheKey: Hashable {
        let path: String
        let cacheBustToken: String
    }

    private let fetchAsset: (String) async throws -> (Data, String)?

    // Track active tasks for cancellation
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let lock = NSLock()

    // Thread-safe deterministic cache (~20MB limit).
    private let cacheCostLimit = 20 * 1024 * 1024
    private var cache: [CacheKey: CachedAsset] = [:]
    private var cacheOrder: [CacheKey] = []
    private var cacheCost = 0
    private let cacheLock = NSLock()

    public init(fetchAsset: @escaping (String) async throws -> (Data, String)?) {
        self.fetchAsset = fetchAsset
        super.init()
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let path = url.path.removingPercentEncoding, !path.isEmpty else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let taskId = ObjectIdentifier(urlSchemeTask as AnyObject)
        let key = CacheKey(path: path, cacheBustToken: Self.cacheBustToken(from: url))

        // Register while holding the lock. `removeTask` takes the same lock, so a
        // request served straight from cache cannot finish and try to remove its
        // entry before that entry exists, which would leave the completed task
        // retained here for the life of the web view.
        lock.lock()
        activeTasks[taskId] = Task { [weak self] in
            guard let self = self else { return }

            do {
                let data: Data
                let mimeType: String

                // Check cache first
                if let cached = self.cachedAsset(for: key) {
                    (data, mimeType) = (cached.data, cached.mimeType)
                } else {
                    // Fetch from remote
                    guard let result = try await self.fetchAsset(path) else {
                        if !Task.isCancelled {
                            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                        }
                        self.removeTask(taskId)
                        return
                    }
                    (data, mimeType) = result
                    self.cacheAsset(data: data, mimeType: mimeType, for: key)
                }

                guard !Task.isCancelled else {
                    self.removeTask(taskId)
                    return
                }

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": mimeType,
                        "Content-Length": String(data.count)
                    ]
                )!

                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                if !Task.isCancelled {
                    urlSchemeTask.didFailWithError(error)
                }
            }

            self.removeTask(taskId)
        }
        lock.unlock()
    }

    /// The renderer re-requests every image with `?_cb=<token>` when the document
    /// is refreshed. Any query at all distinguishes one generation from another.
    private static func cacheBustToken(from url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.query ?? ""
    }

    /// Test seam: the number of tasks still tracked for cancellation.
    var activeTaskCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeTasks.count
    }

    private func removeTask(_ taskId: ObjectIdentifier) {
        lock.lock()
        activeTasks.removeValue(forKey: taskId)
        lock.unlock()
    }

    private func cachedAsset(for key: CacheKey) -> CachedAsset? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = cache[key] else { return nil }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        return cached
    }

    private func cacheAsset(data: Data, mimeType: String, for key: CacheKey) {
        let cached = CachedAsset(data: data, mimeType: mimeType)
        guard cached.cost <= cacheCostLimit else { return }

        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Drop every other generation of this path. Refreshed images are never
        // served from an older token, and the superseded bytes are dead weight.
        for staleKey in cache.keys where staleKey.path == key.path && staleKey != key {
            if let stale = cache.removeValue(forKey: staleKey) {
                cacheCost -= stale.cost
            }
            cacheOrder.removeAll { $0 == staleKey }
        }

        if let previous = cache[key] {
            cacheCost -= previous.cost
            cacheOrder.removeAll { $0 == key }
        }

        while cacheCost + cached.cost > cacheCostLimit, let evictedKey = cacheOrder.first {
            cacheOrder.removeFirst()
            if let evicted = cache.removeValue(forKey: evictedKey) {
                cacheCost -= evicted.cost
            }
        }

        cache[key] = cached
        cacheOrder.append(key)
        cacheCost += cached.cost
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskId = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        let task = activeTasks.removeValue(forKey: taskId)
        lock.unlock()
        task?.cancel()
    }
}
