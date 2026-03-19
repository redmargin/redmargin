# Show Hidden Files in Sidebar

## Meta

- Status: Implemented
- Branch: feature/show-hidden-files

---

## Business

### Goal

Allow users to see and navigate into hidden folders and files (dotfiles/dotfolders) in the sidebar file tree. Replace recursive tree enumeration with lazy single-level loading for all sidebar trees (local and remote).

### Proposal

Add a "Show Hidden Files" toggle as a per-window setting with a global default in Preferences (default: off) and a View menu shortcut (Cmd+Shift+.).

### Behaviors

**Hidden files toggle (done in Phases 1-4):**

- View > Show Hidden Files (Cmd+Shift+.) toggles the setting for the current window
- Menu item title alternates between "Show Hidden Files" and "Hide Hidden Files" based on current window's state
- Per-window state is persisted to UserDefaults (same pattern as sidebar visibility)
- New windows inherit the global default from Preferences
- Hidden files/folders appear inline with normal files, sorted the same way (directories first, then alphabetical)
- `.git` directory remains excluded regardless of the setting (stays in `ignoredDirectories`)
- Other entries in `ignoredDirectories` (`node_modules`, `.build`, etc.) also remain excluded regardless
- Preferences > General includes a "Show hidden files" checkbox in a new "Sidebar" section (sets the default for new windows)

**Lazy sidebar loading (Phase 5):**

- Sidebar loads one directory level at a time, never recurses upfront
- All folders are shown (no markdown-content filter on folders)
- Only markdown files are shown (non-markdown files are still filtered)
- Expanding a folder loads its children on demand (single `contentsOfDirectory` or `listDirectory` call)
- Collapsing a folder keeps its children in memory (no re-fetch on re-expand)
- Toggling hidden files reloads only the currently visible levels
- FSEvents watcher refreshes only the affected directory level, not the entire tree
- Opening a folder or file in the sidebar is instant regardless of directory size

### Out of scope

- Filtering or dimming hidden files visually (they appear identical to normal files)
- Showing hidden files in the system Open panel (that has its own Cmd+Shift+. handled by macOS)

---

## Technical

### Approach

**Hidden files toggle (Phases 1-4, done):** Per-window setting following the sidebar-visibility pattern. Global default in PreferencesManager, per-window `@State`, loaded from DocumentSettingsStorage, View menu toggle with Cmd+Shift+. shortcut. Server-side `.skipsHiddenFiles` removed so all entries are returned; client filters based on the per-window setting.

**Lazy sidebar loading (Phase 5):** Replace the recursive `buildTreeRecursive` in both `FileTreeProvider` and `RemoteFileTreeProvider` with single-level enumeration. This is the standard approach used by Finder, VS Code, and every other file browser.

**FileTreeNode** gains a `childrenLoaded: Bool` flag (default `false`). Directory nodes are created with empty `children` and `childrenLoaded=false`. The disclosure chevron is always shown for directories.

**FileTreeProvider** replaces `buildTreeRecursive` with `loadChildren(for:)` — a single `contentsOfDirectory` call for one directory. On init, it loads the root level only. When a folder node is expanded and `childrenLoaded` is false, the provider loads that folder's children. All folders are included (no markdown-content filter on folders — only files are filtered to markdown). The `showHiddenFiles` flag controls whether `contentsOfDirectory` uses `.skipsHiddenFiles`. Hidden entries starting with `.` are excluded client-side when `showHiddenFiles` is false.

**RemoteFileTreeProvider** replaces `buildTreeRecursive` and the `findMarkdownFiles` path with single-level `listDirectory` calls. The `findMarkdownFiles` RPC is no longer used for tree building (it's inherently recursive). On init, it loads the root level via one `listDirectory` call. Expansion triggers another `listDirectory` for that folder. Same filtering rules.

**Remote directory watcher** continues to use `findMarkdownFiles` for change detection (it tells us which paths changed), but tree rebuilds are now per-directory — only the affected parent directory is re-enumerated instead of the entire tree.

**FSEvents watcher (local)** on change, re-enumerates only the changed directory level rather than rebuilding the entire tree. The watcher already receives per-file events — the provider maps the changed path to its parent directory and reloads that level.

**SidebarView / TreeNodeView** — on expand, calls the provider to load children if not yet loaded. The provider populates children asynchronously and the `@Published children` triggers a UI update.

### Approach Validation

This mirrors the established per-window settings pattern used throughout the codebase. Sidebar visibility uses this exact flow: global default in PreferencesManager, per-window `@State`, loaded from DocumentSettingsStorage at window creation, persisted on change, toggled via View menu notification. No new patterns are introduced.

### Risks

| Risk                                           | Mitigation                                                                                                          |
|------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| Old remote servers won't return hidden files   | Graceful degradation: no hidden entries in remote sidebars until server binary is redeployed. No error shown.       |
| Cmd+Shift+. conflicts with macOS text input    | Not a standard text input shortcut. Finder uses it for hidden files. macOS does not intercept it in non-Finder apps.|

### Implementation Plan

**Phase 1: Preference and Storage**

- [x] Add `showHiddenFiles` property to `PreferencesManager` (`src/Preferences/PreferencesManager.swift`) — Bool, default `false`, persisted to UserDefaults key `RedMargin.Preferences.ShowHiddenFiles`
- [x] Add "Show hidden files" toggle to Preferences > General in a new "Sidebar" section (`src/Preferences/PreferencesView.swift`)
- [x] Add `saveHiddenFilesVisible`/`loadHiddenFilesVisible` methods to `DocumentSettingsStorage` (`AppMain/DocumentSettingsStorage.swift`) for both `URL` and `RemoteLocation`, following the gutter/git-indicators pattern

**Phase 2: Local File Tree**

- [x] Add `showHiddenFiles` property to `FileTreeProvider` (`src/Views/FileTreeProvider.swift`) that triggers `refresh()` on change
- [x] Pass `showHiddenFiles` into `buildTreeRecursive` and conditionally include/exclude `.skipsHiddenFiles` in the `contentsOfDirectory` options
- [x] Add `showHiddenFiles` init parameter to `DocumentWindowContent` (`AppMain/DocumentView.swift`), defaulting to `PreferencesManager.shared.showHiddenFiles`. Add `@State var showHiddenFiles` initialized from it.
- [x] Load `showHiddenFiles` from `DocumentSettingsStorage` in `AppDelegate.openDocument()` (`AppMain/AppDelegate.swift`) and pass it to `DocumentWindowContent`
- [x] Add `showHiddenFiles` init parameter to `FolderWindowContent` (`AppMain/FolderWindowContent.swift`), same pattern. Add `@State var showHiddenFiles` initialized from it.
- [x] Load `showHiddenFiles` from `DocumentSettingsStorage` in `AppDelegate.openFolder()` (`AppMain/AppDelegateFolderAndMenu.swift`) and pass it to `FolderWindowContent`
- [x] In both views, add `onChange(of: showHiddenFiles)` to persist via `DocumentSettingsStorage` and update `fileTreeProvider.showHiddenFiles`

**Phase 3: Remote File Tree**

- [x] Remove `.skipsHiddenFiles` from `findMarkdownFiles` in `Server/FileOperations.swift` (line 60) so the server returns hidden `.md` files
- [x] Remove `.skipsHiddenFiles` from `listDirectory` in `Server/FileOperations.swift` (line 25) so the server returns hidden directory entries
- [x] Add `showHiddenFiles` property to `RemoteFileTreeProvider` (`src/Views/RemoteFileTreeProvider.swift`) that triggers `refresh()` on change
- [x] In `buildTreeRecursive`, skip entries where `entry.name.hasPrefix(".")` unless `showHiddenFiles` is true (after the existing `ignoredDirectories` check)
- [x] In `convertTrieToNodes`, skip directory names and file names starting with `.` unless `showHiddenFiles` is true
- [x] Add `@State var showHiddenFiles` to `RemoteDocumentWindowContent` (`AppMain/RemoteDocumentView.swift`), loaded from `DocumentSettingsStorage` in `.onAppear` (same pattern as `showGutter` and `showGitIndicators` at lines 197-201)
- [x] Add `onChange(of: showHiddenFiles)` to persist via `DocumentSettingsStorage` and update `fileTreeProvider.showHiddenFiles`

**Phase 4: View Menu**

- [x] Add `.toggleHiddenFiles` notification name to `AppDelegateExtensions.swift`
- [x] Add `toggleHiddenFiles` action to `AppDelegate` in `AppDelegateFolderAndMenu.swift` — posts the `.toggleHiddenFiles` notification
- [x] Add "Show Hidden Files" menu item to `createViewMenu` in `MainMenu.swift` with Cmd+Shift+. shortcut and `ViewMenuTag.hiddenFiles` tag, placed after the Sidebar item (before the separator)
- [x] Update `ViewMenuDelegate.menuNeedsUpdate` in `MainMenu.swift` to read per-window hidden files state from `DocumentSettingsStorage` and set the menu item title, following the same pattern as the gutter/sidebar items
- [x] Add `@Binding var showHiddenFiles: Bool` to `NotificationModifiers` in `AppMain/DocumentView.swift`, add `.onReceive(.toggleHiddenFiles)` that toggles it, update the call site to pass `$showHiddenFiles`
- [x] Add `@Binding var showHiddenFiles: Bool` to `FolderNotificationModifiers` in `AppMain/FolderWindowContent.swift`, add `.onReceive(.toggleHiddenFiles)` that toggles it (gate on `checkIsKeyWindow()` only, NOT `hasDocument` — this is a sidebar setting), update the call site to pass `$showHiddenFiles`
- [x] Add `@Binding var showHiddenFiles: Bool` to `RemoteNotificationModifiers` in `AppMain/RemoteDocumentViewModifiers.swift`, add `.onReceive(.toggleHiddenFiles)` that toggles it, update the call site to pass `$showHiddenFiles`

**Phase 5: Lazy Sidebar Loading**

- [x] Add `childrenLoaded: Bool` property to `FileTreeNode` (`src/Views/FileTreeProvider.swift`) — default `false`, set to `true` after children are populated
- [x] Replace `buildTreeRecursive` in `FileTreeProvider` with `loadChildren(for:)` that does a single `contentsOfDirectory` call for one directory — returns `[FileTreeNode]` with directory nodes having empty children and `childrenLoaded=false`
- [x] Update `FileTreeProvider` init to load only the root level (call `loadChildren` for the root directory)
- [x] Add `expandFolder(_:)` method to `FileTreeProvider` — when a directory node is expanded and `childrenLoaded` is false, load its children via `loadChildren`, then set `childrenLoaded=true`. All folders are included; only files are filtered to markdown.
- [x] Hook `expandFolder` into the `onExpandedChange` callback on `FileTreeNode` — when `isExpanded` becomes true and `childrenLoaded` is false, trigger loading
- [x] Update `refresh()` in `FileTreeProvider` to re-enumerate only the root level (and any currently-expanded directories that are already loaded)
- [x] Update FSEvents watcher handler to re-enumerate only the affected parent directory, not rebuild the entire tree
- [x] Replace `buildTreeRecursive` in `RemoteFileTreeProvider` with single-level `listDirectory` calls following the same pattern
- [x] Stop using `findMarkdownFiles` RPC for tree building in `RemoteFileTreeProvider` — use `listDirectory` for all tree operations
- [x] Add `expandFolder(_:)` to `RemoteFileTreeProvider` with the same lazy-load-on-expand behavior
- [x] When `showHiddenFiles` changes, reload all currently visible levels (root + expanded directories) rather than rebuilding the entire tree
- [x] Remove the `buildTreeFromPaths` / `convertTrieToNodes` / `PathTrie` code from `RemoteFileTreeProvider` (no longer needed)
- [x] Update existing hidden-files tests to work with the new lazy loading model
- [x] Rebuild Linux server binary (`resources/scripts/build-linux.sh`) after all changes

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one.

### Unit Tests (`Tests/SidebarTests.swift`)

- [x] `testHiddenFilesExcludedByDefault` - Create a temp directory with `.hidden.md` and `visible.md`, build tree with `showHiddenFiles: false`, assert only `visible.md` appears
- [x] `testHiddenFilesIncludedWhenEnabled` - Same setup, build tree with `showHiddenFiles: true`, assert both files appear
- [x] `testHiddenFoldersExcludedByDefault` - Create a temp directory with `.hidden/` containing a `.md` file and `visible/` containing a `.md` file, assert only `visible/` appears
- [x] `testHiddenFoldersIncludedWhenEnabled` - Same setup with `showHiddenFiles: true`, assert both folders appear
- [x] `testGitDirectoryAlwaysExcluded` - With `showHiddenFiles: true`, assert `.git/` directory is still excluded
- [x] `testIgnoredDirectoriesStillExcludedWhenShowingHidden` - With `showHiddenFiles: true`, assert `node_modules/`, `.build/` etc. remain excluded

### Unit Tests (`Tests/PreferencesManagerTests.swift`)

- [x] `testShowHiddenFilesDefaultsFalse` - Fresh PreferencesManager has `showHiddenFiles == false`
- [x] `testShowHiddenFilesPersists` - Set to `true`, verify UserDefaults key is written

### Unit Tests — Lazy Loading (`Tests/SidebarTests.swift`)

- [x] `testLazyLoadRootOnly` - Create nested dirs with markdown, init provider, assert only root-level entries are present (children of subdirs are empty)
- [x] `testLazyLoadOnExpand` - Create nested dirs, init provider, expand a folder node, assert its children are now populated
- [x] `testAllFoldersShownRegardlessOfMarkdown` - Create a folder with no markdown files inside, assert it still appears in the sidebar
- [x] `testExpandedFolderChildrenSurviveRefresh` - Expand a folder, trigger refresh, assert children are still present

### Manual Verification (Marco)

- [x] Open a folder containing hidden subdirectories (e.g., a repo with `.github/`). Confirm sidebar does not show them by default.
- [x] Press Cmd+Shift+. — confirm hidden folders/files appear in the sidebar immediately (under 1 second, even in HOME).
- [x] Press Cmd+Shift+. again — confirm they disappear.
- [x] Open a second window to a different folder. Toggle hidden files in one window only. Confirm each window maintains its own state independently.
- [ ] Close and reopen a window — confirm the hidden files setting is restored.
- [ ] Open Preferences > General — confirm "Show hidden files" checkbox sets the default for new windows.
- [ ] Open HOME as a folder. Sidebar loads instantly. Expand `.config/` — children load on demand.
- [ ] Open a remote folder on carlowe-dev. Sidebar loads instantly. Expanding folders loads children without lag.
