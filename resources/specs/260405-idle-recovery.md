# Idle Recovery: Fix App Becoming Unresponsive After Sitting Idle

## Meta

- Status: Reviewed
- Branch: fix/idle-recovery

---

## Business

### Goal

Fix the app becoming permanently unresponsive after sitting idle for minutes or hours, requiring a relaunch. Particularly severe with remote documents.

### Proposal

Make Redmargin self-healing: detect when system processes (WebView renderer, file watchers, SSH connections) have been killed or frozen by macOS during idle/sleep, and automatically recover them without user intervention.

### Behaviors

- After system sleep/wake, the app automatically recovers and shows current content within seconds
- After extended idle (hours), the app still responds to file changes and refreshes correctly
- If the WebView renderer process is killed by macOS, the view automatically reloads (no permanent blank screen)
- Remote documents reconnect and re-sync after any connection interruption
- No user action required — recovery is invisible

### Out of scope

- Offline editing or queuing edits while disconnected
- Connection pooling or multiplexing for SSH
- RPC polling replacement (50ms loop → continuation-based)

---

## Technical

### Approach

Five root-cause fixes plus one supporting fix, ordered by impact:

**1. WebView process termination recovery.** macOS kills WKWebView content processes when the app is idle and memory is needed. The app currently has no handler for this — the view goes blank and never recovers. Add `webViewWebContentProcessDidTerminate` to the Coordinator, which resets state flags and calls `loadRenderer` to reload from the file URL (not `reload()`, to explicitly re-establish file access permissions via `loadFileURL(_:allowingReadAccessTo:)`). As a safety net, also check for a dead content process on `NSApplication.didBecomeActiveNotification` by testing `webView.title` — the delegate doesn't always fire reliably.

**2. App Nap prevention.** macOS throttles background apps via App Nap, which freezes timers, dispatch sources, and network I/O. SSH keepalives stop, the server times out the connection, but the client doesn't know. Use `ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason:)` while any remote document is open. This prevents App Nap while still allowing display sleep. Track the activity token and end it when the last remote document closes.

**3. FileWatcher sleep/wake recovery.** The kernel `kqueue`/`vnode` events backing DispatchSource silently stop working after sleep — the dispatch source object still exists but its kernel event source is dead. Listen for `NSWorkspace.didWakeNotification` in FileWatcher itself, tear down the old dispatch source and file descriptor, and create a fresh watcher. Also add an `onWatcherDied` callback so DocumentState can re-establish the watch if all retries fail (currently the watcher silently dies after 5 retries with only a `print()`).

**4. AsyncStream continuation cleanup.** `eventContinuation` and `stateContinuation` in SSHConnection are never `.finish()`-ed. Consumers (`for await` loops in RemoteFileProvider and RemoteDocumentState) hang forever when the connection is torn down, preventing cleanup. Call `.finish()` on both continuations in `disconnect()` and in `handleDisconnect()`, and nil them out afterward.

**5. WKUserContentController message handler cleanup.** `addScriptMessageHandler` creates a strong reference from the content controller to the Coordinator, which is never released because `removeScriptMessageHandler` is never called. Use a weak proxy object (standard `WeakScriptMessageHandler` pattern) that holds a `weak` reference to the real handler, breaking the retain cycle.

### Approach Validation

Research confirmed all five root causes and the proposed fixes:

- **WKWebView termination:** Apple documents `webViewWebContentProcessDidTerminate` as the recovery point. Firefox iOS and Embrace.io both document that the delegate doesn't always fire — a polling/activation check is needed as fallback. Recovery should call `loadRenderer` (which uses `loadFileURL`) rather than `reload()` to explicitly re-establish file access permissions. ([embrace.io](https://embrace.io/blog/webview-thread-terminations/), [nevermeant.dev](https://nevermeant.dev/handling-blank-wkwebviews/), [WebKit Bug 176855](https://bugs.webkit.org/show_bug.cgi?id=176855))
- **App Nap:** `ProcessInfo.processInfo.beginActivity` (not `ProcessInfo()` — common mistake) with `.userInitiatedAllowingIdleSystemSleep` is the documented approach. Verified via alt-tab-macos source. ([Apple docs](https://developer.apple.com/documentation/foundation/processinfo/1415995-beginactivity), [Lapcat Software](https://lapcatsoftware.com/articles/prevent-app-nap.html))
- **DispatchSource after sleep:** The cmux project documented the identical bug (git branch indicator stops updating after sleep). kqueue events silently die — the only fix is tear down and recreate. ([cmux #494](https://github.com/manaflow-ai/cmux/issues/494), [macFUSE #889](https://github.com/macfuse/macfuse/issues/889))
- **AsyncStream finish:** Standard Swift concurrency guidance — consumers block forever without `finish()`. ([Donny Wals](https://www.donnywals.com/understanding-swift-concurrencys-asyncstream/), [Antoine van der Lee](https://www.avanderlee.com/swift/asyncthrowingstream-asyncstream/))
- **WKUserContentController leak:** Well-documented retain cycle. Weak proxy pattern is the standard fix. ([Apple Forums](https://developer.apple.com/forums/thread/706970), [tigi44](https://tigi44.github.io/ios/iOS,-Objective-c-WKWebView-ScriptMessageHandler-Memory-Leak/))

### Risks

| Risk | Mitigation |
| ------ | ------------ |
| WebView recovery causes visible flash | Use the existing fade-in pattern (alphaValue 0→1) during recovery; set webView opacity to 0 before reload, restore after didFinish |
| App Nap prevention increases energy usage | Only active while remote documents are open; uses `.allowingIdleSystemSleep` so display still sleeps; end activity when last remote doc closes |
| FileWatcher wake recreation races with file changes | Fire `onChange` after successful recreation so content is re-read immediately, catching any changes during sleep |
| AsyncStream finish causes unexpected task cancellation | Consumers already handle task cancellation gracefully via `guard !Task.isCancelled` checks |
| Weak proxy breaks message handler functionality | Weak reference only breaks if Coordinator is prematurely deallocated — Coordinator lifetime is tied to the SwiftUI view which owns it |

### Implementation Plan

**Phase 1: WebView process termination recovery**

- [ ] Add `webViewWebContentProcessDidTerminate` to Coordinator in `MarkdownWebView.swift` — reset `isLoaded`, `hasFiredFirstRenderComplete`, `hasRestoredInitialScroll` to false, then call `loadRenderer` to reload the HTML
- [ ] Store a weak `webView` reference on Coordinator (set in `makeNSView`) so the termination handler and activation observer can access it
- [ ] Store a `loadRenderer: ((WKWebView) -> Void)?` closure on Coordinator, set in `makeNSView` to call `self.loadRenderer(webView:)` — `loadRenderer` is already a separate method (line 190), the Coordinator just needs a way to invoke it
- [ ] Add `NSApplication.didBecomeActiveNotification` observer in Coordinator that checks `webView.title` (nil/empty = dead process) and triggers the same recovery via the stored `loadRenderer` closure. Guard against double recovery — if `isLoaded` is already false (termination handler already fired), skip the activation check
- [ ] Store current `RenderParams` in Coordinator so the pending render can be replayed after recovery (the `didFinish` delegate already handles `pendingRender`)
- [ ] Remove the observer in Coordinator cleanup to avoid dangling references

**Phase 2: App Nap prevention for remote documents**

- [ ] Add an activity tracking mechanism (reference-counted) to `SSHConnectionManager` — `beginActivity` when first remote document opens, `endActivity` when last one closes
- [ ] Use `ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Active SSH connections for remote documents")`
- [ ] Store the returned `NSObjectProtocol` token and call `ProcessInfo.processInfo.endActivity()` when count reaches zero
- [ ] Call the increment/decrement from `RemoteDocumentState.init` and `deinit` (or equivalent lifecycle points)

**Phase 3: FileWatcher sleep/wake recovery**

- [ ] Add `NSWorkspace.didWakeNotification` observer in `FileWatcher.init` that tears down the current dispatch source and file descriptor, then calls `startWatching()` to create a fresh watcher. Guard with a `isRecreating` flag to prevent races if wake fires during an in-progress `startWatching()` or `retryStartWatching()`
- [ ] Remove the observer in `FileWatcher.deinit`
- [ ] Add an `onWatcherDied: (() -> Void)?` callback property to `FileWatcher`
- [ ] Call `onWatcherDied` when all 5 retries in `retryStartWatching` are exhausted (instead of just `print()`)
- [ ] In `LocalFileProvider.watchFile`, set `onWatcherDied` to create a new `FileWatcher` with the same URL, callback, and token — transparently replacing the dead watcher without requiring changes to the `FileProvider` protocol or `DocumentState` (which doesn't interact with `FileWatcher` directly; it uses `fileProvider.watchFile()`)
- [ ] Apply the same `didWakeNotification` teardown-and-recreate pattern in `GitRepoWatcher` (`LocalFileProvider.swift`) — its `indexWatcher`, `headWatcher`, and `refWatcher` all use `FileWatcher` and are equally vulnerable to kqueue death after sleep
- [ ] Fire `onChange` after successful watcher recreation on wake, so any file changes during sleep are picked up immediately

**Phase 4: AsyncStream continuation cleanup**

- [ ] In `SSHConnection.disconnect()` (`SSHConnectionExtensions.swift`), call `eventContinuation?.finish()` and `stateContinuation?.finish()` before setting state to `.disconnected`, then nil both continuations
- [ ] In `SSHConnection.handleDisconnect()`, call `.finish()` on both continuations before clearing state, then nil them
- [ ] Add `deinit` to `SSHConnection` (if not present) that calls `.finish()` on both continuations as a safety net
- [ ] Verify that `RemoteFileProvider` and `RemoteDocumentState` `for await` loops exit cleanly after `finish()` is called — they should, since the loop naturally terminates

**Phase 5: WKUserContentController message handler cleanup**

- [ ] Create a `WeakScriptMessageHandler` class in `MarkdownWebView.swift` that implements `WKScriptMessageHandler`, holds a `weak var delegate: WKScriptMessageHandler?`, and forwards `userContentController(_:didReceive:)` to the delegate
- [ ] In `makeNSView`, wrap the Coordinator in `WeakScriptMessageHandler` before passing to `addScriptMessageHandler`
- [ ] Add `dismantleNSView` to the `NSViewRepresentable` that calls `removeAllScriptMessageHandlers()` on the configuration's `userContentController`

**Phase 6: Remote asset cache memory management** *(supporting fix — reduces memory pressure that triggers root cause #1, WKWebView content process termination)*

- [ ] Replace the `cache: [String: (Data, String)]` dictionary and `cacheLock: NSLock` in `RemoteAssetSchemeHandler.swift` with an `NSCache<NSString, CachedAsset>` (where `CachedAsset` is a small class wrapper holding `Data` and `String`, since `NSCache` requires class values)
- [ ] Set `totalCostLimit` to ~20MB (`20 * 1024 * 1024`), using `data.count` as the cost when inserting
- [ ] Remove the manual `cacheLock` — `NSCache` is thread-safe
- [ ] Remove the `getCached` and `setCache` helper methods, replacing with direct `NSCache` calls

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one.

### Unit Tests (`Tests/FileWatcherTests.swift`)

- [ ] `testWatcherCallsOnDiedAfterRetryExhaustion` - Force file deletion, verify `onWatcherDied` callback fires after retries exhaust
- [ ] `testWatcherRecreatesAfterSimulatedWake` - Post `didWakeNotification`, verify watcher still detects subsequent file writes
- [ ] `testGitRepoWatcherRecreatesAfterSimulatedWake` - Create a `GitRepoWatcher` on a temp git repo, post `didWakeNotification`, modify `.git/index`, verify `onChange` fires

### Unit Tests (`Tests/SSHConnectionTests.swift`)

- [ ] `testDisconnectFinishesContinuations` - Call `disconnect()`, verify `events` and `stateChanges` streams terminate (for-await loop exits)
- [ ] `testHandleDisconnectFinishesContinuations` - Simulate unexpected disconnect, verify streams terminate

### Integration Tests

- [ ] `testWebViewRecoveryAfterProcessTermination` - Create a MarkdownWebView, call `webViewWebContentProcessDidTerminate` on its coordinator, verify `isLoaded` resets to false and the renderer reloads (didFinish fires again)
- [ ] `testAppNapActivityStartsWithRemoteDoc` - Open a remote document state, verify `ProcessInfo` activity is active; close it, verify activity ends

### Unit Tests (`Tests/RemoteAssetSchemeHandlerTests.swift`)

- [ ] `testCacheServesSubsequentRequests` - Fetch an asset, fetch again, verify the `fetchAsset` closure is only called once (served from cache)
- [ ] `testCacheEvictsUnderCostLimit` - Insert assets exceeding 20MB total cost, verify earlier entries are evicted (NSCache may evict lazily, so verify count decreases or a known early entry is gone)

### Manual Verification (Marco)

- [ ] Open a local markdown file, put laptop to sleep for 5+ minutes, wake, edit the file externally — verify it auto-refreshes
- [ ] Open a remote markdown file, leave the app idle behind other windows for 30+ minutes, bring it forward — verify content is visible (not blank) and editable
- [ ] Open a remote markdown file, put laptop to sleep for 5+ minutes, wake, edit the file on the server — verify it auto-refreshes within a few seconds
