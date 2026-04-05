import Foundation
import WebKit

/// Wrapper for NSCache values (NSCache requires class types).
private class CachedAsset {
    let data: Data
    let mimeType: String

    init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public class RemoteAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "redmargin-remote"

    private let fetchAsset: (String) async throws -> (Data, String)?

    // Track active tasks for cancellation
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let lock = NSLock()

    // Thread-safe auto-evicting cache (~20MB limit)
    private let cache: NSCache<NSString, CachedAsset> = {
        let cache = NSCache<NSString, CachedAsset>()
        cache.totalCostLimit = 20 * 1024 * 1024
        return cache
    }()

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

        let task = Task { [weak self] in
            guard let self = self else { return }

            do {
                let data: Data
                let mimeType: String

                // Check cache first
                if let cached = self.cache.object(forKey: path as NSString) {
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
                    // Cache for future requests (cost = data size for eviction)
                    self.cache.setObject(
                        CachedAsset(data: data, mimeType: mimeType),
                        forKey: path as NSString,
                        cost: data.count
                    )
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

        lock.lock()
        activeTasks[taskId] = task
        lock.unlock()
    }

    private func removeTask(_ taskId: ObjectIdentifier) {
        lock.lock()
        activeTasks.removeValue(forKey: taskId)
        lock.unlock()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskId = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        let task = activeTasks.removeValue(forKey: taskId)
        lock.unlock()
        task?.cancel()
    }
}
