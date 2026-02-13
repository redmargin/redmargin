# Fix Content Refresh Everywhere

## Meta
- Status: Complete
- Branch: fix/content-refresh

---

## Business

### Goal
Fix broken content refresh across the entire app. Local folder windows never update. Remote files update inconsistently or not at all. Cmd-R does nothing in both cases. The user must relaunch the app to see changes.

### Proposal
Fix three distinct breakages: (1) SwiftUI observation architecture so property changes actually trigger view updates, (2) Linux file watcher so it survives atomic saves, (3) remote refresh so Cmd-R works and errors aren't swallowed.

### Behaviors
After this fix:
- Editing a file externally while it's open in a folder window updates the preview automatically
- Editing a remote file (vim, VS Code on server) updates the preview automatically and keeps working across repeated saves
- Cmd-R re-reads from disk/server and re-renders in all window types, including busting image caches
- Cmd-R also refreshes the sidebar file/folder list when the sidebar is visible
- Failed remote reads surface an error instead of silently doing nothing

### Out of scope
- Migrating other `ObservableObject` types (`FindController`, `PreferencesManager`, `FileTreeProvider`, `RemoteFileTreeProvider`) — they use `@StateObject`/`@ObservedObject` correctly and work fine
- Changes to the JS rendering pipeline — it renders correctly when called

---

## Technical

### Approach

Three independent problems, each with its own fix:

**Problem 1 — SwiftUI observation (local folder windows):** `FolderWindowContent` stores `DocumentState` as `@State private var documentState: DocumentState?`. When an `ObservableObject` is held in `@State`, SwiftUI does not subscribe to its `@Published` property changes. The view never re-evaluates, so `MarkdownWebView.updateNSView()` never fires. This breaks both file watcher updates and Cmd-R in folder windows. `DocumentWindowContent` uses `@StateObject` and works fine — but only because `@StateObject` happens to observe correctly, not because the architecture is sound. Fix: migrate `DocumentState` and `RemoteDocumentState` to `@Observable` (Observation framework, macOS 14+). With `@Observable`, `@State` tracks property access directly, including optionals. This eliminates the entire category of silent observation failures.

**Problem 2 — Linux file watcher dies on atomic saves (remote files):** `LinuxWatcher` uses inotify, which watches by inode. When editors do atomic saves (write temp file, rename over original), `IN_MOVE_SELF` fires but then the watch is dead — still pointing at the old inode. There is no restart/retry logic. The local `FileWatcher` gained retry logic in commit ff1fd53; `LinuxWatcher` has none. Fix: add the same restart-after-atomic-save logic to `LinuxWatcher`. On `IN_DELETE_SELF` or `IN_MOVE_SELF`, close the old watch and re-add with retry/backoff, then fire `onChange`.

**Problem 3 — Remote refresh gaps:** `RemoteDocumentState` has no `refreshToken` property. `RemoteDocumentView` doesn't pass `cacheBust` to `MarkdownWebView`, so Cmd-R can't bust image caches. Additionally, `refresh()` uses `try?` on the remote read, silently swallowing SSH failures. Fix: add `refreshToken` to `RemoteDocumentState`, wire `cacheBust` through `RemoteDocumentView`, and surface read errors in `refresh()` via logging instead of silent swallow.

### Risks

| Risk | Mitigation |
|------|------------|
| `@Observable` has different observation semantics than `ObservableObject` — computed properties aren't automatically observed | Both state classes use only stored properties for published state; no computed properties are involved |
| `@StateObject` guarantees object lifecycle across view updates; `@State` with `@Observable` must provide the same guarantee | `@State` with `@Observable` objects has identical lifecycle semantics in SwiftUI — Apple's documented migration path |
| LinuxWatcher restart logic could miss events during the retry window | Same risk exists in the local FileWatcher (accepted); exponential backoff with small initial delay (0.1s) minimizes the window |
| inotify re-watch may fail if file doesn't exist yet after atomic save | Retry with backoff handles this — file appears within milliseconds of the rename |

### Implementation Plan

**Phase 1: Migrate DocumentState to @Observable**
- [x] `AppMain/DocumentState.swift` — Replace `ObservableObject` with `@Observable` macro, remove all `@Published` wrappers, add `import Observation` if needed
- [x] `AppMain/DocumentView.swift` — Change `@StateObject private var state: DocumentState` to `@State private var state: DocumentState`
- [x] `AppMain/FolderWindowContent.swift` — Already `@State`, verify it compiles and observes correctly
- [x] Build and verify folder window refresh works (file watcher + Cmd-R)

**Phase 2: Migrate RemoteDocumentState to @Observable**
- [x] `AppMain/RemoteDocumentState.swift` — Replace `ObservableObject` with `@Observable` macro, remove all `@Published` wrappers
- [x] `AppMain/RemoteDocumentView.swift` — Change `@StateObject private var state: RemoteDocumentState` to `@State private var state: RemoteDocumentState`
- [x] Build and verify remote document windows still work

**Phase 3: Fix LinuxWatcher atomic save handling**
- [x] `Server/Watcher.swift` `LinuxWatcher` — On `IN_DELETE_SELF` or `IN_MOVE_SELF`, close the old inotify watch, retry re-adding with exponential backoff (same pattern as `FileWatcher.retryStartWatching`), then fire `onChange`
- [x] Verify on devtest: open file in Redmargin, edit with vim (atomic save), confirm watcher survives and content updates

**Phase 4: Wire up remote refresh properly**
- [x] `AppMain/RemoteDocumentState.swift` — Add `refreshToken` property, increment in `refresh()` and `loadFile()`
- [x] `AppMain/RemoteDocumentView.swift` — Pass `cacheBust: state.refreshToken` to `MarkdownWebView`
- [x] `AppMain/RemoteDocumentState.swift` `refresh()` — Replace `try?` with `do/catch`, log errors explicitly
- [x] Build and verify Cmd-R works for remote files

**Phase 5: Cmd-R refreshes sidebar**
- [x] `AppMain/FolderWindowContent.swift` — In the `.refreshDocument` notification handler, also call `fileTreeProvider.refresh()` when `showSidebar` is true
- [x] `AppMain/DocumentView.swift` — Same: call `fileTreeProvider.refresh()` in the `.refreshDocument` handler when sidebar is visible
- [x] `AppMain/RemoteDocumentView.swift` — Same for remote windows
- [x] Build and verify Cmd-R refreshes both content and sidebar file list

**Phase 6: Clean up**
- [x] Add code comment on `refreshToken` in both state classes clarifying its sole purpose is image cache busting, not triggering view updates
- [x] Verify `reloadContent()` in both state classes does NOT need `refreshToken` (SwiftUI now observes `content` changes directly via `@Observable`)

---

## Testing

Tests in `Tests/`. Results logged in `Tests/TEST_LOG.md`.

### Unit Tests (`Tests/DocumentStateTests.swift`)

- [x] `testReloadContentUpdatesContent` - Simulating a file change triggers content update on DocumentState
- [x] `testRefreshIncrementsToken` - Calling refresh() increments refreshToken and re-reads content
- [x] `testLoadFileUpdatesAllState` - Loading a new file updates fileURL, content, refreshToken, and clears git state

### Unit Tests (`Tests/LinuxWatcherTests.swift`)

- [x] `testWatcherSurvivesAtomicSave` - Rename-over-original triggers onChange and watcher keeps working for subsequent changes
- [x] `testWatcherRetriesOnDeleteSelf` - File deletion triggers retry logic and watcher recovers when file reappears

### Manual Verification (Marco)

Visual inspection items that cannot be automated:
- [x] Open a markdown file in a folder window, edit it externally — preview updates without relaunching
- [x] Press Cmd-R in a folder window — content re-renders (visible with image changes or added text)
- [x] Open a file via double-click (single-document window) — file watcher and Cmd-R still work
- [x] Open a remote file, edit with vim on server — preview updates and keeps updating across multiple saves
- [x] Press Cmd-R on a remote file — content re-renders including image cache bust
- [x] Press Cmd-R with sidebar open — file list refreshes (add/remove a file externally, Cmd-R shows it)
