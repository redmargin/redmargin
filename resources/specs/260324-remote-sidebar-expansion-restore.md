# Remote Sidebar Expansion Restore

## Meta

- Status: Done
- Branch: fix/remote-sidebar-expansion-restore

---

## Business

### Goal

Fix remote folder windows so the sidebar opens quickly and still restores the user's saved expanded folders after relaunch.

### Proposal

Keep remote sidebar root loading fast by rendering the initial tree first, then restore persisted expansion state asynchronously. Saved folder expansion should still reappear after relaunch, but it must not block the first paint of the sidebar.

### Behaviors

User-facing behaviors:

- Opening a remote file or remote folder shows the sidebar quickly instead of waiting on all saved expanded subfolders to load first.
- Saved expanded remote folders are restored after relaunch, including nested folders.
- Remote top-level folders stay collapsed unless the user explicitly expanded them before.

### Out of scope

- Local sidebar expansion restore changes.
- New persistence keys or migration logic.

---

## Technical

### Approach

Update `src/Views/RemoteFileTreeProvider.swift` so initial remote root loading only fetches the root level and does not eagerly walk persisted expanded folders on the critical path. Persisted remote expansion state should be loaded from `DocumentSettingsStorage`, but applied in a follow-up async restore pass after `rootNodes` is published and `isLoading` can complete.

Add a focused test seam for remote sidebar tree loading so `Tests/SidebarTests.swift` can validate two regressions: remote root loads do not eagerly expand top-level folders by default, and persisted nested expansion restores after initial load without holding `isLoading` open for child RPCs.

### Approach Validation

The regression was introduced by `45cb330`, which moved remote expanded-folder restore into the initial load path and awaited nested child loads before the sidebar could finish loading. That fixed one symptom (restore eventually happening) by regressing another (slow initial open). The existing remote tree provider already uses lazy single-level loading, so the correct fix is to keep that lazy behavior for first paint and run saved expansion restore afterward instead of synchronously during root load.

### Risks

| Risk | Mitigation |
| ---- | ---------- |
| Async restore task mutates stale tree state after a reconnect or reload | Track the active load generation and ignore stale restore work |
| Saved expansion no longer restores nested folders | Add a test that restores nested remote folders and asserts descendants become visible after the async restore completes |
| Top-level remote folders still load eagerly | Add a test that verifies root load performs only the root listing when there is no saved expansion |

### Implementation Plan

**Phase 1: Remote tree loading**

- [x] Update `src/Views/RemoteFileTreeProvider.swift` so persisted remote expanded folders are applied after root nodes are loaded instead of before `loadRootLevel(from:)`
- [x] Ensure remote directory nodes start collapsed unless their path exists in the persisted expanded-folder set
- [x] Guard async restore work against stale reloads or reconnect-triggered reloads

**Phase 2: Regression coverage**

- [x] Add remote sidebar provider test coverage in `Tests/RemoteSidebarTests.swift` for fast initial root loading without eager child enumeration
- [x] Add remote sidebar provider test coverage in `Tests/RemoteSidebarTests.swift` for nested persisted expansion restore after initial load

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one. Omit test types that don't apply.

### Unit Tests (`Tests/RemoteSidebarTests.swift`)

- [x] `testRemoteFileTreeProviderDoesNotEagerlyExpandTopLevelFoldersOnInitialLoad` - Root remote load only lists the root directory when no folders are saved as expanded
- [x] `testRemoteFileTreeProviderRestoresNestedExpandedFoldersAfterInitialLoad` - Persisted nested remote expansion restores after the initial root load finishes
- [x] `testRemoteFileTreeProviderInitialLoadCompletesBeforeExpandedChildrenFinishLoading` - `isLoading` clears after root load even when restoring expanded descendants requires slower child listings
