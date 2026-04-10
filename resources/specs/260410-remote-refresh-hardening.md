# Remote Refresh Hardening

## Meta

- Status: Draft
- Branch: fix/remote-refresh-hardening

---

## Business

### Goal

Fix the remaining remote refresh regressions so remote documents, remote folders, and remote sidebars recover consistently after stale SSH connections, reconnects, manual refreshes, and repeated refresh attempts.

### Proposal

Make remote refresh behavior deterministic and bounded: document refreshes read documents, folder refreshes refresh folder trees, sidebar refreshes cannot hang indefinitely, and stale connection objects do not keep reconnecting after they have been replaced.

### Behaviors

User-facing behaviors:

- Pressing Refresh in a remote document re-reads the current remote file and refreshes the visible sidebar when the sidebar is open.
- Pressing Refresh in a remote folder with no selected file refreshes only the sidebar tree and does not try to read the folder path as a Markdown file.
- Pressing the sidebar refresh button in a remote folder with no selected file refreshes only the sidebar tree.
- After SSH reconnect, the remote sidebar reloads its root and visible expanded folders, then re-registers directory watches so future remote file additions, deletions, and renames continue to appear.
- Repeated remote sidebar refreshes do not stack overlapping refresh work. The newest refresh wins, stale refresh tasks cannot replace newer state, and timeout leaves the previous tree visible.
- Remote sidebars show loading feedback while an explicit sidebar refresh is running.
- Opening another remote document on a stale host does not leave an abandoned SSH connection continuing to reconnect in the background.

### Out of scope

- Replacing the SSH transport or RPC framing.
- Replacing server push notifications with polling.
- Offline editing or queuing edits while disconnected.
- Connection pooling, multiplexing, or multi-host connection architecture changes.
- Local file refresh behavior.
- Visual redesign of the sidebar or refresh controls.

---

## Technical

### Approach

Use the same reliable reconnect signal for remote sidebars that remote documents already use. `RemoteFileTreeProvider` should observe `.sshConnectionReconnected` through `NotificationCenter`, filter by host, call `loadFiles()` on matching reconnects, and remove its observer in `deinit`. Remove the `stateChanges`-based sidebar reload path because the actual reconnect sequence passes through `.connecting` before `.connected`, so the current `.reconnecting -> .connected` adjacency check misses successful reconnects.

Separate remote document refresh from remote folder refresh in `RemoteDocumentWindowContent`. Add a small helper that decides whether the current window has a selected document. The notification refresh handler and `SidebarView` refresh handler must call `state.refresh()` only when a document is selected; otherwise they call only `fileTreeProvider.refresh()`. This keeps remote folder mode from treating a directory path as a file and forcing reconnects on expected directory-read failures.

Restore bounded, single-owner refresh behavior in `RemoteFileTreeProvider.refresh()`. Reintroduce a tracked refresh task, generation counter, loading state, cancellation, and a hard timeout. Refactor the visible-level merge so refresh work for expanded folders is awaited inside the current refresh task rather than launched as untracked child `Task`s from `mergeLevel`. On timeout or cancellation, leave the existing tree untouched and clear loading only for the active generation.

Tighten `SSHConnectionManager` connection ownership. The manager should keep one reusable connection object per host and return cached `.connected`, `.connecting`, `.reconnecting`, and recoverable `.disconnected` connections to callers. When a cached connection is not responsive, the manager triggers the existing force-reconnect path on that same object and returns it, then callers use the existing fast-fail readiness checks to wait for recovery. When the manager replaces a cached connection that was intentionally closed by manager APIs, it first stops the old connection so reconnect tasks, health checks, streams, and reconnect notifications cannot continue after the object has been removed from the cache.

### Approach Validation

This spec is based on the prior refresh history in this repo: `1800357` fixed infinite remote sidebar spinners with timeout and generation checks, `210d1e2` fixed remote watcher re-registration after reconnect, `88f45b0` made remote refresh ping before read, `2c018fa` made sidebar file navigation fast-fail on hung connections, and `c0c6686` stopped stale remote restore entries from retrying forever. The current code keeps the document refresh improvements but lost some sidebar safeguards during lazy tree loading.

The local SSH debugging doc (`resources/docs/260120-ssh-remote-connection-debugging.md`) already records that NotificationCenter became the reliable reconnection signal after AsyncStream state observation proved unreliable for recovery. Apple documents NotificationCenter as the standard mechanism for named in-process notifications and observer registration, which matches the existing document-state pattern. Apple also documents using `beginActivity` and `endActivity` for long user-initiated work that should not be deferred by App Nap, validating the current App Nap guard while reinforcing that abandoned connection tasks should be stopped. The Linux inotify manual documents automatic watch removal through `IN_IGNORED` and non-recursive directory event semantics, supporting the existing one-watch-per-visible-directory sidebar design and the need to re-register watches after reconnect.

Relevant references:

- [Apple Notification Programming Topics](https://developer.apple.com/library/archive/documentation/General/Conceptual/DevPedia-CocoaCore/Notification.html)
- [Apple Energy Efficiency Guide for Mac Apps: Prioritize Work at the App Level](https://developer-mdn.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)
- [Linux inotify manual](https://man7.org/linux/man-pages/man7/inotify.7.html)

### Risks

| Risk | Mitigation |
| ------ | ------------ |
| Sidebar reloads twice after reconnect because both state stream and notification fire | Make NotificationCenter the only reload trigger for reconnect recovery in `RemoteFileTreeProvider`; leave state stream usage out of data reloads. |
| Timeout clears a useful sidebar tree and shows an empty state | On timeout, preserve existing `rootNodes` and only log the timeout; loading state clears for the active generation. |
| Refresh cancellation leaves expanded folders half-updated | Perform visible-level refresh in one tracked task and apply merged root state only after all awaited visible levels for that generation complete. |
| Folder-mode refresh no longer refreshes an already-selected empty Markdown file | Use `isFolderMode` as the deciding state, not `content.isEmpty`. `loadFile(at:)` already sets `isFolderMode = false` after a file selection. |
| Stopping replaced SSH connections breaks active remote windows | Keep reusable connections in the manager cache and recover them in place; stop only intentionally closed connections the manager is replacing. |
| Tests keep asserting obsolete disconnected force-reconnect behavior | Update the test to match the current intended behavior: a disconnected connection can start a fresh reconnect path, and cleanup must stop it. |

### Implementation Plan

**Phase 1: Remote Sidebar Reconnect Recovery**

- [ ] Update `src/Views/RemoteFileTreeProvider.swift` to accept and store an optional `reconnectHost` string.
- [ ] Update both `RemoteFileTreeProvider` initializers in `src/Views/RemoteFileTreeProvider.swift` to take `reconnectHost`, defaulting to `nil` for tests and local-only callers.
- [ ] In `src/Views/RemoteFileTreeProvider.swift`, add a stored NotificationCenter observer token for `.sshConnectionReconnected`.
- [ ] In `src/Views/RemoteFileTreeProvider.swift`, when `reconnectHost` is present and the notification object matches it, call `loadFiles()` on the main actor.
- [ ] In `src/Views/RemoteFileTreeProvider.swift`, remove the reconnect observer in `deinit`.
- [ ] In the remote document initializer in `AppMain/RemoteDocumentView.swift`, pass `location.host` into `RemoteFileTreeProvider`.
- [ ] In the remote folder initializer in `AppMain/RemoteDocumentView.swift`, pass `host` into `RemoteFileTreeProvider`.
- [ ] Remove the `stateChanges` observer from `RemoteFileTreeProvider` so data reload is not dependent on the `.reconnecting -> .connected` adjacency.

**Phase 2: Remote Folder Refresh Routing**

- [ ] Add a helper in `AppMain/RemoteDocumentView.swift` that refreshes the selected document only when `isFolderMode == false`, and always refreshes `fileTreeProvider` when the sidebar refresh path requires it.
- [ ] Update the `.refreshDocument` handler in `AppMain/RemoteDocumentView.swift` to use the helper instead of always calling `state.refresh()`.
- [ ] Update the `SidebarView` `onRefresh` closure in `AppMain/RemoteDocumentView.swift` to use the helper instead of always calling `state.refresh()`.
- [ ] Keep remote document windows unchanged from the user's perspective: selected files still refresh content and sidebar together.

**Phase 3: Bounded Remote Sidebar Refresh**

- [ ] Add a tracked `refreshTask` and `refreshGeneration` to `src/Views/RemoteFileTreeProvider.swift`.
- [ ] Update `refresh()` in `src/Views/RemoteFileTreeProvider.swift` to cancel the previous refresh task, increment the generation, set `isLoading = true`, and start one tracked refresh task.
- [ ] Add a 15-second timeout to `RemoteFileTreeProvider.refresh()` that preserves existing `rootNodes` on timeout.
- [ ] Ensure only the active refresh generation can mutate `rootNodes` or clear `isLoading`.
- [ ] Refactor `mergeLevel` in `src/Views/RemoteFileTreeProvider.swift` into an async visible-level refresh path that awaits child directory listings for already-loaded expanded folders.
- [ ] Remove untracked `Task` creation from `mergeLevel` in `src/Views/RemoteFileTreeProvider.swift`.
- [ ] Preserve node identity for unchanged paths so sidebar selection, scroll stability, and expanded state remain stable after refresh.
- [ ] Keep directory watch registration tied to visible directories: root and expanded loaded folders are watched, collapsed folder descendants are unwatched.

**Phase 4: SSH Connection Manager Ownership**

- [ ] Add a manager-facing reuse method to `src/Core/Remote/Client/SSHConnection.swift` that reports whether a cached connection was not intentionally closed.
- [ ] Update `src/Core/Remote/Client/SSHConnectionManager.swift` so `connection(for:)` returns cached reusable `.connected`, `.connecting`, `.reconnecting`, and `.disconnected` connections instead of replacing them.
- [ ] When `connection(for:)` finds a reusable cached connection that is not alive, call `forceReconnect()` on that cached connection before returning it.
- [ ] When `connection(for:)` replaces a non-reusable cached connection, call `disconnect()` on the old connection before removing it from `connections`.
- [ ] Ensure `disconnect(host:)` and `disconnectAll()` remain the only paths that intentionally close active cached connections.
- [ ] Keep `ensureConnectionReady(fileProvider:)` in `AppMain/AppDelegateExtensions.swift` as the fast-fail readiness check for callers that receive an existing reconnecting connection.

**Phase 5: Test Alignment**

- [ ] Update `Tests/SSHConnectionTests.swift` so force reconnect on a disconnected connection asserts the intended fresh reconnect path and performs cleanup.
- [ ] Add focused remote sidebar reconnect tests in `Tests/RemoteSidebarTests.swift`.
- [ ] Add focused remote sidebar refresh timeout and cancellation tests in `Tests/RemoteSidebarTests.swift`.
- [ ] Add `AppMain/RemoteRefreshRouting.swift` with a small testable refresh-routing helper used by `RemoteDocumentWindowContent`.
- [ ] Add focused remote folder refresh routing coverage for `AppMain/RemoteRefreshRouting.swift`.

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one.

### Unit Tests (`Tests/RemoteSidebarTests.swift`)

- [ ] `testRemoteSidebarReloadsOnMatchingReconnectNotification` - Posts `.sshConnectionReconnected` for the provider host and verifies `loadFiles()` re-lists the root and re-registers directory watches.
- [ ] `testRemoteSidebarIgnoresReconnectForOtherHost` - Posts `.sshConnectionReconnected` for a different host and verifies no additional directory list or watch registration occurs.
- [ ] `testRemoteSidebarRefreshCancelsPreviousRefresh` - Starts a slow refresh, triggers a second refresh, and verifies only the second generation updates `rootNodes`.
- [ ] `testRemoteSidebarRefreshTimeoutPreservesExistingTree` - Makes `listDirectory` exceed the timeout and verifies the existing tree remains visible and `isLoading` clears.
- [ ] `testRemoteSidebarRefreshReloadsExpandedVisibleFolders` - Expands a folder, changes the fake provider entries for that folder, calls `refresh()`, and verifies the expanded folder's children update without rebuilding unrelated collapsed descendants.
- [ ] `testRemoteSidebarRefreshSetsLoadingWhileActive` - Calls `refresh()` with a delayed provider and verifies `isLoading` becomes true during the refresh and false after completion.

### Unit Tests (`Tests/RemoteRefreshRoutingTests.swift`)

- [ ] `testRemoteFolderRefreshWithoutSelectionSkipsDocumentRefresh` - Verifies the refresh-routing helper returns sidebar-only refresh for remote folder mode before any file is selected.
- [ ] `testRemoteFolderRefreshWithSelectionRefreshesDocumentAndSidebar` - Verifies the refresh-routing helper returns document-and-sidebar refresh after a remote file has been selected.
- [ ] `testRemoteDocumentRefreshRefreshesDocumentAndSidebar` - Verifies normal remote document windows keep the current document refresh behavior.

### Unit Tests (`Tests/SSHConnectionTests.swift`)

- [ ] `testForceReconnectOnDisconnectedConnectionStartsReconnectPath` - Updates the existing disconnected force-reconnect test to assert the current intended behavior and then disconnects to stop the reconnect task.
- [ ] `testConnectionManagerReturnsExistingReconnectingConnection` - Registers a reconnecting connection for a host and verifies `connection(for:)` returns that connection instead of creating a replacement.
- [ ] `testConnectionManagerDisconnectsNonReusableConnectionBeforeReplacement` - Registers a non-reusable cached connection, calls `connection(for:)`, and verifies the old connection is disconnected before a replacement is stored.

### Integration Tests (`Tests/RemoteIntegrationTests.swift`)

- [ ] `testRemoteDirectoryWatchRecoversAfterReconnect` - Using the `devtest` SSH alias, expands a remote folder, forces reconnect, modifies that folder, and verifies the sidebar receives the update after reconnect.
- [ ] `testRemoteFolderSidebarRefreshDoesNotForceDocumentReconnect` - Opens a remote folder with no selected file, triggers sidebar refresh, and verifies no document read is attempted for the folder path.
