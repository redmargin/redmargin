# Remote Window Restore UX Overhaul

## Meta

- Status: Draft
- Branch: feature/remote-restore-ux

---

## Business

### Goal

Make reopening previously open remote windows instant and calm: windows come back immediately at their old positions showing their last-seen contents, the window you are using keeps focus, and a slow or unreachable host never holds up the rest or makes the app feel stuck.

### Proposal

When the app reopens, restore every remote window right away from a local copy of its last contents, connect only the window you were last using straight away, connect the rest quietly in the background or when you switch to them, and show any connection trouble inline on the affected window instead of stalling the whole reopen.

### Behaviors

User-facing behaviors:

- On launch, each previously open remote window reappears at its saved position and size showing its last-seen contents, with no wait for the server.
- Windows reappear in their previous front-to-back order; the window that was active last is the one left in front. No window jumps in front of another while reopening, and the app does not pull itself forward on its own as windows fill in.
- The previously active remote window connects immediately and shows live content. The other remote windows connect quietly in the background, and connecting one is brought forward the moment you switch to it.
- While a window is connecting, it shows a small, unobtrusive "Connecting…" indicator and keeps its last-seen contents readable.
- A remote window whose host cannot be reached shows a small inline "No route to <host>" message with a "Retry" control, keeps showing its last-seen contents, and does not affect any other window.
- Reopening time no longer grows with the number of slow or unreachable windows.
- Once a window is connected, file changes, the git gutter, checkbox toggles, and the existing "remote file changed" conflict prompt all behave as before.

### Acceptance Criteria

- [ ] **A1** Reopening previously open remote windows shows them immediately at their previous positions and sizes, with their last-seen contents, without waiting for any server.
- [ ] **A2** While remote windows reopen, focus stays on the window in use: no window jumps in front of another, and the app does not bring itself forward on its own as windows fill in.
- [ ] **A3** Reopened remote windows appear in their previous front-to-back order, with the previously active window left in front.
- [ ] **A4** A remote window whose host cannot be reached shows an inline "No route" message with a Retry control and keeps its last-seen contents; the other windows are unaffected.
- [ ] **A5** Reopening time does not grow with the number of slow or unreachable windows: two unreachable windows reopen as fast as one.
- [ ] **A6** The previously active remote window is connected and live right after launch; the other windows connect quietly in the background or when first switched to.
- [ ] **A7** Switching to a not-yet-connected remote window connects it promptly and shows its live, current content; pressing Retry on a failed window attempts the connection again.
- [ ] **A8** Once connected, checkbox toggles save to the server and a server-side change detected on connect is surfaced through the existing conflict prompt.

### Out of scope

- Replacing the SSH transport or RPC framing, or introducing SSH connection multiplexing (ControlMaster/ControlPersist).
- Caching the git gutter state across launches; the gutter is recomputed once a window connects.
- Changes to local (non-remote) document or folder window restoration behavior.
- Offline editing or queuing edits while disconnected, beyond the existing pending-checkbox-toggle behavior.

---

## Technical

### Approach

Three changes work together. First, **decouple a remote window from a live connection**: a restored window is created from a local content cache with a `RemoteFileProvider` whose `SSHConnection` exists but has not connected yet, and `RemoteDocumentState` gains an explicit presentation phase (`onDemand` / `connecting` / `connected` / `unavailable`) that drives the existing status overlay and gates file-watch/git startup until the connection is live. Second, **make restore passive and instant**: `AppDelegate.restoreRemoteDocuments` creates all windows synchronously from cache and places them with `NSWindow.orderFront`/`order(_:relativeTo:)` in saved back-to-front order, making only the previously frontmost window key exactly once at the end — never `makeKeyAndOrderFront` or `NSApp.activate(ignoringOtherApps:)` per window, and never the blocking restore panel. Third, **connect lazily and fast-fail**: only the frontmost window connects on launch, the rest connect through a bounded, low-priority background warm pass and on window focus, all funnelled through one single-flight-per-host `SSHConnectionManager.ensureConnected`; hard-unreachable failures are classified into `SSHConnectionError.hostUnreachable` on the deploy/connect path and never retried, while transient timeouts retry with exponential backoff plus jitter (at most three attempts).

Areas affected: `AppMain/AppDelegate.swift`, `AppMain/AppDelegateFolderAndMenu.swift`, `AppMain/AppDelegateExtensions.swift`, `AppMain/RemoteDocumentState.swift`, `AppMain/RemoteDocumentView.swift`, `src/Core/Remote/Client/SSHConnectionManager.swift`, `src/Core/Remote/Client/SSHConnection.swift`, `src/Core/Remote/Client/SSHConnectionExtensions.swift`, `src/Core/Remote/Client/ServerDeployer.swift`, and a new `src/Core/Remote/Client/RemoteContentCache.swift`. The global `RestoreProgressWindow` stays for explicit URL-scheme remote opens (`processPendingRemoteLaunches`) but is no longer used by session restore.

### Approach Validation

Researched current best practice across three areas before writing this spec.

- **Connection strategy.** AWS's reliability guidance is explicit that hard-unreachable errors (`ENETUNREACH`/`EHOSTUNREACH`) will not self-heal and must not be retried, and that transient retries need exponential backoff with jitter and a small attempt cap. RFC 8305 connection racing applies to multiple addresses of one host; for many distinct hosts the technique to borrow is bounded-concurrency parallel connect with fast-fail, which is what the background warm pass does. Measured on the affected machine: the saved `wraith` host (10.250.55.56) has no route over the current WiFi and each `ssh` attempt costs ~7s before failing, so today's blind 3x retry with 0s/3s/5s backoff on a serial per-host loop turns one dead host into ~29s and two into ~1min.
- **macOS window choreography.** Apple's AppKit documentation distinguishes `orderFront(_:)` (places a window without making it key/main and without activating the app) from `makeKeyAndOrderFront(_:)` (takes key and fights for front); `activate(ignoringOtherApps:)` is deprecated on macOS 14. Restoring a set passively with `orderFront`/`order(_:relativeTo:)` and making only the previously frontmost window key once is the documented non-focus-stealing pattern. The current per-window `makeKeyAndOrderFront` + `NSApp.activate` in `openRemoteDocument`/`openRemoteFolder` is the direct cause of windows jumping in front while the user reads another.
- **Prior art.** iTerm2, VS Code Remote-SSH, and browsers all restore window chrome and last-known content instantly from local cache, connect lazily/on-demand (Firefox `restore_on_demand`), show per-window inline reconnect status rather than a global modal, and reveal without changing focus (Panic Nova shipped a fix for exactly the "terminal steals focus on restore" bug). This spec mirrors that: instant cached restore, lazy connect, inline status, passive ordering.

The existing codebase already supports the pieces: `parseSSHStderr` maps "network is unreachable"/"no route to host" to `.hostUnreachable`, `shouldRecoverRemoteOperation` already treats that as non-recoverable, `RemoteDocumentState` already has a connection-status overlay and an `.sshConnectionReconnected` NotificationCenter pattern, and `SSHConnectionManager` already shares one connection per host. The gap is that the restore/deploy path throws an unclassified `ServerDeployerError`, so the fast-fail never triggers there, and that windows require loaded content plus a live connection at creation time.

Relevant references:

- [RFC 8305 Happy Eyeballs v2](https://www.rfc-editor.org/rfc/rfc8305)
- [AWS Builders' Library: timeouts, retries, and backoff with jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/)
- [Apple AppKit: NSWindow.orderFront(_:)](https://developer.apple.com/documentation/appkit/nswindow/orderfront(_:))
- [Apple AppKit: NSWindow.order(_:relativeTo:)](https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:))
- [iTerm2 session restoration](https://iterm2.com/documentation-restoration.html)
- [VS Code Remote-SSH](https://code.visualstudio.com/docs/remote/ssh)

### Risks

| Risk | Mitigation |
| ---- | ---------- |
| A window created before its connection exists triggers file-watch/git work against a dead connection and hangs | Gate `setupFileWatcher`, `detectGitChanges`, connection-state observation, and the App Nap activity token behind the first successful connect inside `connectIfNeeded`; an on-demand window starts in the `onDemand` phase doing no network work. |
| Two windows on the same host both trigger a first connect and race the deploy/handshake | Funnel every connect through `SSHConnectionManager.ensureConnected(for:)`, which keeps one connection per host and coalesces concurrent callers onto a single in-flight connect task. |
| Stale cached content is shown as if current after connecting | On connect, revalidate by reading the file; if it differs, replace content and refresh the cache and gutter, reusing the existing `applyServerContent` path and conflict prompt. |
| Background warm floods the network and competes with the frontmost window | Warm runs at `.utility` priority with bounded concurrency (max three hosts in flight), skips the frontmost host and any already-connected host, and fast-fails unreachable hosts with no retry. |
| Lowering `ConnectTimeout` to 5s breaks a genuinely slow but reachable host | 5s comfortably covers the LAN/Tailscale fleet in use; transient timeouts still retry with backoff, and a window that times out shows inline status with Retry rather than failing silently. |
| Dropping the per-location `test -e` existence probe lets a deleted file reopen | On connect, a file-not-found read result puts the window in `unavailable(.fileNotFound)` with its cached content still visible and a Retry control, instead of silently dropping the window. |
| Restored remote windows fight local/folder restore for front position | Remote restore only ever uses `orderFront`/`order(_:relativeTo:)`; the single key-window decision for the whole launch stays in `restoreFrontmostWindow`, called once after all windows exist. |
| Window z-order cannot be rebuilt because order was never saved for remote windows | Persist remote window back-to-front order on quit under a new key and rebuild from it on restore. |

### Implementation Plan

**Phase 1: Local content cache**

- [x] **T1** Add `src/Core/Remote/Client/RemoteContentCache.swift` (in `RedmarginCore`): an actor with an injectable base directory (default `Application Support/Redmargin/RemoteContentCache`) exposing `save(_ content: String, for: RemoteLocation)`, `load(for: RemoteLocation) -> String?`, and `evict(for: RemoteLocation)`. Store one file per location named by a stable SHA-256 of `RemoteLocation.storageKey`. Skip caching content larger than a 4 MB cap, and keep at most 200 entries by evicting the least-recently-written file when the cap is exceeded. The injectable base directory lets tests use a temp directory.
- [x] **T2** In `AppMain/RemoteDocumentState.swift`, write to `RemoteContentCache` whenever server content is confirmed: in `applyServerContent(_:for:)`, after the initial content is set in `init`, and after a successful `fileProvider.writeFile` in `handleCheckboxToggle` (where `lastKnownServerContent` is updated). Cache writes are fire-and-forget and must not block the UI.

**Phase 2: On-demand connection model**

- [x] **T3** In `src/Core/Remote/Client/SSHConnectionManager.swift`, add `preregisterConnection(for host: String) -> SSHConnection` that returns the cached connection for the host if one exists, otherwise creates a fresh (not-yet-connected) `SSHConnection(host:)`, caches it, and returns it. This lets a window and its `RemoteFileProvider` be built before any connect happens, with all windows on a host sharing one connection.
- [x] **T4** In `src/Core/Remote/Client/SSHConnectionManager.swift`, add `ensureConnected(for host: String) async throws -> SSHConnection`: return the cached connection if `isAlive()`; otherwise connect it via a single-flight per-host task stored in a `[String: Task<Void, Error>]` map so concurrent callers await one connect. Reuse the existing connection object (call its `connect()`), and on failure rethrow the thrown `SSHConnectionError` and clear the in-flight entry. Keep the existing `connection(for:)` behavior intact for current callers.
- [x] **T5** In `AppMain/RemoteDocumentState.swift`, add `enum RemoteConnectionPhase: Equatable { case onDemand; case connecting; case connected; case unavailable(RemoteUnavailableReason) }` and `enum RemoteUnavailableReason { case noRoute; case refused; case authFailed; case fileNotFound; case serverError }`, plus an observed `connectionPhase` property. Keep the existing `connectionState` for live transport state; `connectionPhase` is what the overlay reads.
- [x] **T6** In `AppMain/RemoteDocumentState.swift`, add an `init` parameter `connectsOnDemand: Bool = false`. When true, do not run the `init` task that begins App Nap activity, sets up the file watcher, detects git changes, or starts connection-state observation; instead set `connectionPhase = .onDemand`. When false (current callers), behavior is unchanged and `connectionPhase = .connected`.
- [x] **T7** In `AppMain/RemoteDocumentState.swift`, add `func connectIfNeeded(force: Bool = false) async`: no-op if already `.connecting` or `.connected` and not `force`; set `connectionPhase = .connecting`; call `SSHConnectionManager.shared.ensureConnected(for: location.host)`. On success, begin App Nap activity, start the file watcher, git detection, and connection-state observation (the work currently in `init`), set `connectionPhase = .connected`, then revalidate by reading the file and applying/caching it if it changed. On `SSHConnectionError.hostUnreachable` set `.unavailable(.noRoute)`, on `.connectionRefused` set `.unavailable(.refused)`, on `.authenticationFailed` set `.unavailable(.authFailed)` — none of these retry. On transient `SSHConnectionError` cases (`.operationTimeout`, `.handshakeTimeout`, `.serverNotResponding`, `.connectionTimeout`, `.helperStartupTimeout`, `.unexpectedDisconnect`) retry with exponential backoff plus full jitter, at most three attempts, then set `.unavailable(.serverError)`. If the revalidating read throws a `RemoteFileError` with `isFileNotFound`, set `.unavailable(.fileNotFound)` while keeping cached content visible.
- [x] **T8** In `AppMain/RemoteDocumentState.swift`, in the connection-state observation started by `connectIfNeeded`, mirror live transport changes into `connectionPhase` (`.connecting`/`.reconnecting` → `.connecting`, `.connected` → `.connected`) so a window connected by the background warm pass (which also drives `ensureConnected`) reflects its real state without a second connect path.
- [x] **T9** Add a NotificationCenter name `.remoteWindowConnectRequest` (object: `RemoteLocation.storageKey` string) in `src/Core/Remote/Client/SSHConnectionTypes.swift`. In `RemoteDocumentState.init` observe it, filtered to this window's location, and call `connectIfNeeded()` on match; remove the observer in `deinit`.

**Phase 3: Inline status UI**

- [x] **T10** Add a pure helper (e.g. `RemoteStatusPresentation` in `AppMain/RemoteDocumentView.swift` or a small sibling file) mapping `(connectionPhase, hasContent: Bool)` to an overlay descriptor: whether to show a corner pill or a centered placeholder, the label text, whether to dim the content, and whether to show a Retry action. Soft states (`.connecting`, `.onDemand` with content) use a non-dimming corner pill; states with no cached content use a centered placeholder with a subtle backdrop; `.unavailable(...)` uses a non-dimming pill with a Retry action.
- [x] **T11** Add a small reusable `RemoteStatusPill` SwiftUI view (label, optional SF Symbol, optional action button) used by the overlay for the non-dimming corner indicator.
- [x] **T12** Rewrite `connectionStatusOverlay` in `AppMain/RemoteDocumentView.swift` to render from `RemoteStatusPresentation(state.connectionPhase, hasContent: !state.content.isEmpty)`: `.connecting` → "Connecting…" pill; `.unavailable(.noRoute)` → "No route to \(location.host)" pill with a "Retry" button calling `state.connectIfNeeded(force: true)`; `.unavailable(.refused)`/`.authFailed`/`.serverError`/`.fileNotFound` → matching message with Retry; `.connected` → nothing. Remove the unconditional `Color.black.opacity(0.3)` backdrop for soft states; apply a subtle backdrop only for the no-content centered placeholder. Keep the separate `isRefreshing`/`isExporting` overlay unchanged.

**Phase 4: Passive, instant restore**

- [x] **T13** In `AppMain/AppDelegate.swift`, persist remote window back-to-front order on quit: in `applicationWillTerminate` (alongside the existing `windowOrderKey` save) write the ordered list of `"remote:host:path"` strings derived from `NSApp.orderedWindows` mapped through `remoteDocumentWindows`, reversed to back-to-front, under a new key `RedMargin.RemoteWindowOrder`.
- [x] **T14** In `AppMain/AppDelegateExtensions.swift`, add `func makeOnDemandRemoteWindow(location: RemoteLocation, cachedContent: String) -> NSWindow`: call `SSHConnectionManager.shared.preregisterConnection(for: location.host)`, build a `RemoteFileProvider(connection:)` around it, build `RemoteDocumentWindowContent(content: cachedContent, location:, fileProvider:, ...)` with `connectsOnDemand: true` (thread the flag through the `RemoteDocumentWindowContent` init into `RemoteDocumentState`), call `createRemoteWindow`, set `window.delegate = self`, register in `remoteDocumentWindows`, and return the window without ordering it.
- [x] **T15** Rewrite `restoreRemoteDocuments(_:)` in `AppMain/AppDelegateFolderAndMenu.swift` to be synchronous window creation with no per-host retry loop and no `test -e` probe: read `RemoteContentCache` for each saved location (empty string when absent), build each window with `makeOnDemandRemoteWindow`, and place windows passively in saved back-to-front order from `RedMargin.RemoteWindowOrder` (fall back to saved-array order) using `orderFront(nil)` for the first and `order(.above, relativeTo:)` for each subsequent window. Do not call `makeKeyAndOrderFront`, `NSApp.activate`, `beginRestoreActivity`, or the failed-locations re-save here. Clear `openRemoteLocationsKey` is no longer needed mid-restore because all windows open; leave the existing terminate-time save (`applicationShouldTerminate`) as the source of the open-locations list.
- [x] **T16** In `AppMain/AppDelegate.swift` `applicationDidFinishLaunching`, call `restoreRemoteDocuments` synchronously before the existing final window-ordering step, and ensure `restoreFrontmostWindow()` runs once after all local, folder, and remote windows exist as the single place that makes a window key. Confirm no other restore code path calls `NSApp.activate(ignoringOtherApps:)` for remote restore.

**Phase 5: Lazy connect triggers and background warm**

- [x] **T17** In `AppMain/AppDelegate.swift`, after restore, immediately trigger the connection for the previously frontmost remote window (if the frontmost is remote) by posting `.remoteWindowConnectRequest` for its location, so the window the user lands on is live first.
- [x] **T18** In `AppMain/AppDelegate.swift`, add a background warm pass: a `Task(priority: .utility)` that, over the non-frontmost restored remote windows, triggers their connection through `.remoteWindowConnectRequest` with bounded concurrency of at most three in flight at a time (track in-flight count, skip hosts already connected). Each request reuses each window's `connectIfNeeded`, so `SSHConnectionManager.ensureConnected` dedupes per host and hard-unreachable hosts fast-fail into each window's `unavailable` state with no retry.
- [x] **T19** In `AppMain/AppDelegate.swift` (the `NSWindowDelegate` conformance), implement `windowDidBecomeKey(_:)`: if the window maps to an entry in `remoteDocumentWindows` and is not yet connected, post `.remoteWindowConnectRequest` for its location so focusing a not-yet-connected window connects it promptly.

**Phase 6: Fast-fail classification, timeouts, and jitter**

- [x] **T20** In `src/Core/Remote/Client/ServerDeployer.swift`, when the combined check `ssh` call in `ensureServerDeployed` exits non-zero, classify `checkResult.stderr` with `parseSSHStderr(_:host:)` and throw the resulting `SSHConnectionError` (so "network is unreachable"/"no route to host" becomes `.hostUnreachable`, "connection refused" becomes `.connectionRefused`, auth failures become `.authenticationFailed`) instead of `ServerDeployerError.connectionFailed`. Keep `ServerDeployerError` for architecture and upload failures. This makes `SSHConnection.connect()` propagate a typed, correctly non-retryable error during restore and warm.
- [x] **T21** Lower the connect-path SSH `ConnectTimeout` from 10 to 5 seconds: in `ServerDeployer.sshOptions` and in the proxy `ssh` arguments in `SSHConnection.establishConnectionInternal` (`src/Core/Remote/Client/SSHConnection.swift`). Leave `ServerAliveInterval=15`/`ServerAliveCountMax=3` unchanged.
- [x] **T22** Add full jitter to reconnect backoff in `src/Core/Remote/Client/SSHConnectionExtensions.swift` `scheduleReconnect`: change the delay from `pow(2, attempts)` to a value drawn uniformly from `0...min(maxReconnectDelay, pow(2, attempts))`. Use the same full-jitter formula for the transient-retry loop in `RemoteDocumentState.connectIfNeeded`.
- [x] **T23** Verify and lock in that `SSHConnection.connect()`'s quick-retry-and-redeploy cascade runs only for transient errors (`.handshakeTimeout`, `.serverNotResponding`, `.connectionTimeout`, `.helperStartupTimeout`) and that `.hostUnreachable`, `.connectionRefused`, and `.authenticationFailed` throw immediately with no retry and no redeploy.

---

### Implementation Notes

Decisions taken during implementation (both confirmed with Marco):

- **Test strategy: pure logic + real devtest, no fakes.** Honoring the project's no-mocks convention, the connection state machine's decisions are factored into pure, closure-driven helpers (`RemoteConnectRetry` for the retry policy / jittered backoff / retry loop, `RemoteRestoreOrdering` for z-order, `RemoteStatusPresentation` for the overlay, `RemoteUnavailableReason.forConnectError` for the error→reason map, and `parseSSHStderr` for stderr classification) and tested deterministically. Behavioral connect/revalidate/warm/focus paths are tested against the real `devtest` host; unreachable fast-fail is tested against an unroutable host. The connect tests originally grouped under `Tests/RemoteDocumentStateTests.swift` (T39–T43) are realized as a mix of offline state tests and `devtest`/unroutable integration tests.
- **Remote folder windows restore on-demand with a lazy tree.** Folder locations (trailing-slash paths) are restored passively like document windows, in folder mode; their file tree defers loading until the window connects, driven by a new per-window `.remoteWindowDidConnect` signal that `RemoteFileTreeProvider` observes.

Other notable details: the on-demand connection logic lives in a sibling extension file `AppMain/RemoteDocumentStateConnection.swift` (to stay under the type-body length limit); `RemoteContentCache.loadSync` is a non-isolated synchronous read so restore pulls cached content without an actor hop; an App-Nap `didBeginActivity` flag prevents an on-demand window that never connects from releasing a token it never took.

## Testing

Tests are implementation tasks — the implementer writes and passes each one on the dev surface. Numbering continues from the Implementation Plan. Use real temp directories and real fixtures, no mocks, per project conventions.

### Unit Tests (`Tests/RemoteContentCacheTests.swift`)

- [x] **T24** `testCacheRoundTrip` - Saving content for a location and loading it back returns the same content, using an injected temp base directory.
- [x] **T25** `testCacheMissReturnsNil` - Loading a location that was never cached returns nil.
- [x] **T26** `testCacheSkipsOversizedContent` - Content above the 4 MB cap is not written and loads back as nil.
- [x] **T27** `testCacheEvictsLeastRecentlyWritten` - Exceeding the 200-entry cap evicts the oldest-written entry and keeps the newest.
- [x] **T28** `testEvictRemovesEntry` - `evict(for:)` deletes a previously cached entry so a later load returns nil.

### Unit Tests (`Tests/RemoteRestoreOrderingTests.swift`)

- [x] **T29** `testRestoreOrderRebuildsSavedZOrder` - A pure ordering helper, given a saved back-to-front order and the saved frontmost location, returns the placement sequence back-to-front and identifies the single window to make key.
- [x] **T30** `testRestoreOrderFallsBackToArrayOrderWhenNoSavedOrder` - With no saved z-order, the helper falls back to the saved-array order and still selects the saved frontmost (or the last placed window when no frontmost is recorded).

### Unit Tests (`Tests/RemoteConnectRetryPolicyTests.swift`)

- [x] **T31** `testHardUnreachableIsNotRetryable` - The retry-policy classifier returns "no retry" for `.hostUnreachable`, `.connectionRefused`, and `.authenticationFailed`.
- [x] **T32** `testTransientErrorsAreRetryable` - The classifier returns "retry" for `.operationTimeout`, `.handshakeTimeout`, `.serverNotResponding`, `.connectionTimeout`, `.helperStartupTimeout`, and `.unexpectedDisconnect`.
- [x] **T33** `testBackoffWithJitterStaysWithinBounds` - The full-jitter backoff for attempt n returns a value in `0...min(maxDelay, 2^n)` and the retry loop caps at three attempts.
- [x] **T34** `testServerDeployerClassifiesUnreachableStderr` - "network is unreachable" and "no route to host" stderr classify to `.hostUnreachable`; "connection refused" to `.connectionRefused`; "permission denied"/"publickey" to `.authenticationFailed`.

### Unit Tests (`Tests/RemoteStatusPresentationTests.swift`)

- [x] **T35** `testConnectingWithContentShowsNonDimmingPill` - `(.connecting, hasContent: true)` maps to a corner pill, no dimming, no Retry.
- [x] **T36** `testConnectingWithoutContentShowsPlaceholder` - `(.connecting, hasContent: false)` maps to a centered placeholder with a subtle backdrop.
- [x] **T37** `testNoRouteShowsRetry` - `.unavailable(.noRoute)` maps to a non-dimming pill with a Retry action and a host-named label.
- [x] **T38** `testConnectedShowsNothing` - `.connected` maps to no overlay.

### Unit Tests (`Tests/RemoteDocumentStateTests.swift`)

- [x] **T39** `testOnDemandWindowDoesNoNetworkUntilConnect` - A state created with `connectsOnDemand: true` and a recording fake provider performs no file read, watch, or git call until `connectIfNeeded` is called, and starts in `.onDemand`.
- [x] **T40** `testConnectIfNeededReachesConnectedAndRevalidates` - With a fake provider/connection that connects successfully and returns changed content, `connectIfNeeded` transitions `.onDemand` → `.connecting` → `.connected`, starts the watcher and git detection, applies the new content, and writes it to the cache.
- [x] **T41** `testConnectIfNeededNoRouteIsTerminal` - A fake that throws `.hostUnreachable` puts the state in `.unavailable(.noRoute)` with no retry, leaving cached content visible.
- [x] **T42** `testConnectIfNeededRetriesTransientThenConnects` - A fake that throws one transient error then succeeds reaches `.connected` after a single jittered retry, within the three-attempt cap.
- [x] **T43** `testConnectRequestNotificationTriggersConnect` - Posting `.remoteWindowConnectRequest` for the state's location calls `connectIfNeeded`; posting it for another location does not.

### Unit Tests (`Tests/SSHConnectionManagerTests.swift`)

- [x] **T44** `testPreregisterReturnsSharedConnectionPerHost` - `preregisterConnection(for:)` returns the same connection instance for repeated calls with the same host and a distinct one for a different host.
- [x] **T45** `testEnsureConnectedCoalescesConcurrentCallers` - Two concurrent `ensureConnected(for:)` calls for one host result in a single underlying connect attempt.

### Integration Tests (`Tests/RemoteIntegrationTests.swift`)

All integration tests use the `devtest` SSH alias and run with a 60-second timeout guard, per project conventions.

- [x] **T46** `testOnDemandWindowShowsCachedContentBeforeConnect` - Pre-seed the cache for a `devtest` location, build an on-demand state, and assert the cached content is present and no connection exists before `connectIfNeeded`, then live content after.
- [x] **T47** `testFrontmostConnectsAndOthersWarmInBackground` - Restore two `devtest` windows; assert the frontmost is connected shortly after launch and the second reaches connected via the background warm pass without an explicit focus.
- [x] **T48** `testFocusTriggersConnectForOnDemandWindow` - With background warm disabled in the test harness, assert that simulating key-window focus on a not-yet-connected window drives it to connected.
- [x] **T49** `testUnreachableHostFailsFastWithoutRetryStorm` - Build an on-demand state for a guaranteed-unreachable host (a `192.0.2.0/24` TEST-NET address) and assert `connectIfNeeded` resolves to `.unavailable(.noRoute)` within a few seconds and issues no additional connect attempts.

### UI Verification (`macos-ui-automation` MCP, implementer-run)

- [ ] **T50** Restore two remote windows and confirm via the `macos-ui-automation` MCP that the previously frontmost window is the key window and that the restored windows match their saved front-to-back order (confirms A2, A3).
- [ ] **T51** With another application frontmost, launch Redmargin with restored remote windows and confirm via the MCP that Redmargin does not become the active application on its own and that no remote window changes z-order when a slow window's connection completes (confirms A2).
