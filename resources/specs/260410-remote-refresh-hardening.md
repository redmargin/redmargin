# Remote Refresh Hardening

## Meta

- Status: Implemented
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

The local SSH debugging doc (`resources/docs/260120-ssh-remote-connection-debugging.md`) already records that NotificationCenter became the reliable reconnection signal after AsyncStream state observation proved unreliable for recovery. Apple documents NotificationCenter as a named in-process notification and observer-registration API, which matches the existing document-state pattern. Apple also documents using `beginActivity` and `endActivity` for long user-initiated work that should not be deferred by App Nap, validating the current App Nap guard while reinforcing that abandoned connection tasks should be stopped. The Linux inotify manual documents automatic watch removal through `IN_IGNORED` and non-recursive directory event semantics, supporting the existing one-watch-per-visible-directory sidebar design and the need to re-register watches after reconnect.

Relevant references:

- [Apple Notification Programming Topics](https://developer.apple.com/library/archive/documentation/General/Conceptual/DevPedia-CocoaCore/Notification.html)
- [Apple Energy Efficiency Guide for Mac Apps: Prioritize Work at the App Level](https://developer-mdn.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)
- [Linux inotify manual](https://man7.org/linux/man-pages/man7/inotify.7.html)

Spec review confirmed the approach is sound. All four changes (NotificationCenter for sidebar reconnect, conditional refresh routing, bounded refresh with generation tracking, connection reuse in the manager) use patterns already proven in this codebase. No external research warranted — these are internal plumbing fixes, not new user-facing design decisions.

### Risks

| Risk | Mitigation |
| ------ | ------------ |
| Sidebar reloads twice after reconnect because both state stream and notification fire | Make NotificationCenter the only reload trigger for reconnect recovery in `RemoteFileTreeProvider`; leave state stream usage out of data reloads. |
| Timeout clears a useful sidebar tree and shows an empty state | On timeout, preserve existing `rootNodes` and only log the timeout; loading state clears for the active generation. |
| Refresh cancellation leaves expanded folders half-updated | Perform visible-level refresh in one tracked task, stage root and child changes off to the side, and commit them only after all awaited visible levels for that generation complete. |
| A reconnect reload races with a manual sidebar refresh and stale refresh results replace the reloaded tree | Cancel active refresh work when `loadFiles()` starts and require refresh commits to match both the captured root path and the current `loadGeneration`. |
| Folder-mode refresh no longer refreshes an already-selected empty Markdown file | Use `isFolderMode` as the deciding state, not `content.isEmpty`. `loadFile(at:)` already sets `isFolderMode = false` after a file selection. |
| Stopping replaced SSH connections breaks active remote windows | Keep reusable connections in the manager cache and recover them in place; stop only intentionally closed connections the manager is replacing. |
| Tests keep asserting obsolete disconnected force-reconnect behavior | Update the test to match the current intended behavior: a disconnected connection can start a fresh reconnect path, and cleanup must stop it. |

### Implementation Plan

**Phase 1: Remote Sidebar Reconnect Recovery**

- [x] Update `src/Views/RemoteFileTreeProvider.swift` to accept and store an optional `reconnectHost` string.
- [x] Update both `RemoteFileTreeProvider` initializers in `src/Views/RemoteFileTreeProvider.swift` to take `reconnectHost`, defaulting to `nil` for tests and local-only callers.
- [x] In `src/Views/RemoteFileTreeProvider.swift`, add a stored NotificationCenter observer token for `.sshConnectionReconnected`.
- [x] In `src/Views/RemoteFileTreeProvider.swift`, when `reconnectHost` is present and the notification object matches it, call `loadFiles()` on the main actor.
- [x] In `src/Views/RemoteFileTreeProvider.swift`, remove the reconnect observer in `deinit` and cancel any active refresh or expanded-folder restore task.
- [x] In the remote document initializer in `AppMain/RemoteDocumentView.swift`, pass `location.host` into `RemoteFileTreeProvider`.
- [x] In the remote folder initializer in `AppMain/RemoteDocumentView.swift`, pass `host` into `RemoteFileTreeProvider`.
- [x] Remove the `observeConnectionState` method and `stateObserverTask` from `RemoteFileTreeProvider` so data reload is not dependent on the `.reconnecting -> .connected` adjacency.
- [x] Remove the `stateChanges` parameter from both `RemoteFileTreeProvider` initializers (the public `RemoteFileProvider` init and the internal `RemoteFileTreeProviding` init) since it is no longer used for data reload.
- [x] Update the remote document initializer in `AppMain/RemoteDocumentView.swift` (line 67-74) to stop passing `stateChanges: fileProvider.stateChanges` to `RemoteFileTreeProvider`.
- [x] Update the remote folder initializer in `AppMain/RemoteDocumentView.swift` (line 102-110) to stop passing `stateChanges: fileProvider.stateChanges` to `RemoteFileTreeProvider`.

**Phase 2: Remote Folder Refresh Routing**

- [x] Add `AppMain/RemoteRefreshRouting.swift` with a testable refresh-routing helper that returns whether to refresh the document, the sidebar, or both. Inputs are `isFolderMode`, whether the sidebar is visible, and the refresh source (`commandRefresh` from `RemoteNotificationModifiers` or `sidebarButton` from `SidebarView`).
- [x] Update the `onRefresh` closure passed to `RemoteNotificationModifiers` in `AppMain/RemoteDocumentView.swift` (line 132-135) to use the routing helper: call `state.refresh()` only when the route includes document refresh, and call `fileTreeProvider.refresh()` when the route includes sidebar refresh. For `commandRefresh`, sidebar refresh is included when `isFolderMode == true` or the sidebar is visible.
- [x] Update the `SidebarView` `onRefresh` closure in `AppMain/RemoteDocumentView.swift` (line 200-203) to use the routing helper instead of always calling `state.refresh()`. For `sidebarButton`, sidebar refresh is always included.
- [x] Keep remote document windows unchanged from the user's perspective: selected files still refresh content and sidebar together.

**Phase 3: Bounded Remote Sidebar Refresh**

- [x] Add a tracked `refreshTask` and `refreshGeneration` to `src/Views/RemoteFileTreeProvider.swift`.
- [x] Update `refresh()` in `src/Views/RemoteFileTreeProvider.swift` to cancel the previous refresh task, increment the generation, set `isLoading = true`, and start one tracked refresh task.
- [x] Update `loadFiles()` in `src/Views/RemoteFileTreeProvider.swift` to cancel the active `refreshTask` before incrementing `loadGeneration`, so reconnect reloads cannot be overwritten by an older manual refresh.
- [x] Add a configurable `refreshTimeout: TimeInterval` property to `RemoteFileTreeProvider`, defaulting to 15 seconds in production. Tests inject a shorter value (0.5 seconds) to avoid slow test suites.
- [x] Apply the `refreshTimeout` in `RemoteFileTreeProvider.refresh()` to preserve existing `rootNodes` on timeout.
- [x] Ensure only the active refresh generation can mutate `rootNodes` or clear `isLoading`; before mutating, verify that the captured root path still equals `rootDirectory` and the captured `loadGeneration` still matches the provider's current `loadGeneration`.
- [x] Refactor `mergeLevel` in `src/Views/RemoteFileTreeProvider.swift` into an async visible-level refresh path that awaits child directory listings for already-loaded expanded folders.
- [x] Remove untracked `Task` creation from `mergeLevel` in `src/Views/RemoteFileTreeProvider.swift`.
- [x] Stage refreshed child arrays during visible-level merge and apply them only after the full refresh succeeds; timeout or cancellation must not mutate existing `FileTreeNode.children`.
- [x] Preserve node identity for unchanged paths so sidebar selection, scroll stability, and expanded state remain stable after refresh.
- [x] Keep directory watch registration tied to visible directories: root and expanded loaded folders are watched, collapsed folder descendants are unwatched.

**Phase 4: SSH Connection Manager Ownership**

- [x] Add an `isReusable` computed property to `src/Core/Remote/Client/SSHConnection.swift` that returns `!isIntentionallyDisconnected`. This distinguishes connections that exhausted reconnect attempts or lost connectivity (reusable — the manager can force-reconnect them) from connections that were intentionally closed via `disconnect()` or `disconnectAll()` (not reusable — the manager should replace them).
- [x] Update `src/Core/Remote/Client/SSHConnectionManager.swift` so `connection(for:)` checks `isReusable` on cached connections. If reusable, return the cached connection (regardless of its current state: `.connected`, `.connecting`, `.reconnecting`, or `.disconnected`). If not reusable, replace it.
- [x] When `connection(for:)` finds a reusable cached connection where `isAlive()` returns false, call `forceReconnect()` on that cached connection before returning it.
- [x] When `connection(for:)` replaces a non-reusable cached connection, capture and remove the old connection from `connections`, await `disconnect()` on it, then create and store the replacement connection. This stops orphaned reconnect tasks, health checks, and notification observers from running on a discarded connection object while avoiding reentrant manager calls returning the discarded object.
- [x] Ensure `disconnect(host:)` and `disconnectAll()` remain the only paths that intentionally close active cached connections.
- [x] Keep `ensureConnectionReady(fileProvider:)` in `AppMain/AppDelegateExtensions.swift` as the fast-fail readiness check for callers that receive an existing reconnecting connection.

**Phase 5: Test Alignment**

- [x] Extend `TestRemoteTreeFileProvider` in `Tests/RemoteSidebarTests.swift` to track watched directory paths (add a `recordedWatchPaths()` method alongside the existing `recordedListPaths()`), so reconnect tests can verify watch re-registration.
- [x] Rename and update the existing `testForceReconnectOnDisconnectedConnectionIsNoop` test in `Tests/SSHConnectionTests.swift` to assert the intended fresh reconnect path: after `forceReconnect()` on a `.disconnected` connection, state should transition to `.reconnecting`, and the test must call `disconnect()` afterward to stop the spawned reconnect task.
- [x] Add focused remote sidebar reconnect tests in `Tests/RemoteSidebarTests.swift`.
- [x] Add focused remote sidebar refresh timeout and cancellation tests in `Tests/RemoteSidebarTests.swift`, using a short injected `refreshTimeout` (0.5 seconds).
- [x] Add focused remote folder refresh routing tests in `Tests/RemoteRefreshRoutingTests.swift`.

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one.

### Unit Tests (`Tests/RemoteSidebarTests.swift`)

- [x] `testRemoteSidebarReloadsOnMatchingReconnectNotification` - Posts `.sshConnectionReconnected` for the provider host and verifies `loadFiles()` re-lists the root and re-registers directory watches (verified via `recordedWatchPaths()` on the test fixture).
- [x] `testRemoteSidebarIgnoresReconnectForOtherHost` - Posts `.sshConnectionReconnected` for a different host and verifies no additional directory list or watch registration occurs.
- [x] `testRemoteSidebarRefreshCancelsPreviousRefresh` - Starts a slow refresh, triggers a second refresh, and verifies only the second generation updates `rootNodes`.
- [x] `testRemoteSidebarRefreshTimeoutPreservesExistingTree` - Creates a provider with `refreshTimeout: 0.5`, makes `listDirectory` exceed that timeout, and verifies the existing tree remains visible and `isLoading` clears.
- [x] `testRemoteSidebarRefreshReloadsExpandedVisibleFolders` - Expands a folder, changes the fake provider entries for that folder, calls `refresh()`, and verifies the expanded folder's children update without rebuilding unrelated collapsed descendants.
- [x] `testRemoteSidebarRefreshSetsLoadingWhileActive` - Calls `refresh()` with a delayed provider and verifies `isLoading` becomes true during the refresh and false after completion.

### Unit Tests (`Tests/RemoteRefreshRoutingTests.swift`)

- [x] `testRemoteFolderCommandRefreshWithoutSelectionSkipsDocumentRefresh` - Verifies the routing helper returns sidebar-only refresh when `isFolderMode == true` and the refresh source is `commandRefresh`, regardless of sidebar visibility.
- [x] `testRemoteFolderSidebarButtonRefreshWithoutSelectionSkipsDocumentRefresh` - Verifies the routing helper returns sidebar-only refresh when `isFolderMode == true` and the refresh source is `sidebarButton`.
- [x] `testRemoteFolderCommandRefreshWithSelectionRefreshesDocumentAndVisibleSidebar` - Verifies the routing helper returns document-and-sidebar refresh when `isFolderMode == false`, the refresh source is `commandRefresh`, the sidebar is visible, and a file has been selected.
- [x] `testRemoteFolderSidebarButtonRefreshWithSelectionRefreshesDocumentAndSidebar` - Verifies the routing helper returns document-and-sidebar refresh when `isFolderMode == false`, the refresh source is `sidebarButton`, and a file has been selected.
- [x] `testRemoteDocumentRefreshWithHiddenSidebarRefreshesDocumentOnly` - Verifies the routing helper returns document-only refresh for non-folder remote document windows when the refresh source is `commandRefresh` and the sidebar is hidden.
- [x] `testRemoteDocumentRefreshWithVisibleSidebarRefreshesDocumentAndSidebar` - Verifies the routing helper returns document-and-sidebar refresh for non-folder remote document windows when the refresh source is `commandRefresh` and the sidebar is visible.

### Unit Tests (`Tests/SSHConnectionTests.swift`)

- [x] `testForceReconnectOnDisconnectedConnectionStartsReconnectPath` - Replaces the existing `testForceReconnectOnDisconnectedConnectionIsNoop`. Asserts that `forceReconnect()` on a `.disconnected` connection transitions state to `.reconnecting` and starts a reconnect task, then calls `disconnect()` to clean up.
- [x] `testConnectionManagerReturnsExistingReconnectingConnection` - Registers a reconnecting connection (where `isReusable == true`) for a host and verifies `connection(for:)` returns that same connection instance instead of creating a replacement.
- [x] `testConnectionManagerDisconnectsNonReusableConnectionBeforeReplacement` - Registers a non-reusable cached connection (`isIntentionallyDisconnected == true`), calls `connection(for:)`, and verifies `disconnect()` was called on the old connection before a replacement is stored.

### Integration Tests (`Tests/RemoteIntegrationTests.swift`)

All integration tests use the `devtest` SSH alias and must run with a 60-second timeout guard to prevent hangs (per project conventions).

- [x] `testRemoteDirectoryWatchRecoversAfterReconnect` - Expands a remote folder, forces reconnect, modifies that folder, and verifies the sidebar receives the update after reconnect.
- [x] `testRemoteFolderSidebarRefreshDoesNotForceDocumentReconnect` - Opens a remote folder with no selected file, triggers sidebar refresh, and verifies no document read is attempted for the folder path.
