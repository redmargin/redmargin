# Show Hidden Files in Sidebar

## Meta

- Status: Reviewed
- Branch: feature/show-hidden-files

---

## Business

### Goal

Allow users to see and navigate into hidden folders and files (dotfiles/dotfolders) in the sidebar file tree.

### Proposal

Add a "Show Hidden Files" toggle as a per-window setting with a global default in Preferences (default: off) and a View menu shortcut (Cmd+Shift+.).

### Behaviors

- View > Show Hidden Files (Cmd+Shift+.) toggles the setting for the current window
- Menu item title alternates between "Show Hidden Files" and "Hide Hidden Files" based on current window's state
- Toggling refreshes the current window's sidebar immediately
- Per-window state is persisted to UserDefaults (same pattern as sidebar visibility)
- New windows inherit the global default from Preferences
- Hidden files/folders appear inline with normal files, sorted the same way (directories first, then alphabetical)
- `.git` directory remains excluded regardless of the setting (stays in `ignoredDirectories`)
- Other entries in `ignoredDirectories` (`node_modules`, `.build`, etc.) also remain excluded regardless
- Preferences > General includes a "Show hidden files" checkbox in a new "Sidebar" section (sets the default for new windows)
- Setting persists across app restarts via UserDefaults

### Out of scope

- Filtering or dimming hidden files visually (they appear identical to normal files)
- Showing hidden files in the system Open panel (that has its own Cmd+Shift+. handled by macOS)

---

## Technical

### Approach

This follows the per-window pattern used by sidebar visibility: global default in `PreferencesManager`, per-window `@State` in the view, loaded from `DocumentSettingsStorage` at window creation, persisted on change.

**PreferencesManager** gets a new `showHiddenFiles: Bool` property (default `false`), persisted to UserDefaults. This serves as the default for new windows.

**DocumentSettingsStorage** gets `saveHiddenFilesVisible`/`loadHiddenFilesVisible` methods for both local (`URL`) and remote (`RemoteLocation`) documents, following the existing gutter/git-indicators pattern.

**FileTreeProvider** currently passes `.skipsHiddenFiles` to `contentsOfDirectory(at:includingPropertiesForKeys:options:)`. It gains a `showHiddenFiles` property. When true, the `.skipsHiddenFiles` option is removed. Changing the property triggers a refresh.

**RemoteFileTreeProvider** has two code paths: the `findMarkdownFiles` server call and the recursive `listDirectory` fallback. Both currently receive data from a server that skips hidden files. After server changes (see below), the client filters: in `buildTreeRecursive`, skip entries where `entry.name.hasPrefix(".")` unless `showHiddenFiles` is true. In `buildTreeFromPaths` / `convertTrieToNodes`, skip directory and file names starting with `.` unless `showHiddenFiles` is true. Same `showHiddenFiles` property with refresh on change.

**Server changes** — Both `findMarkdownFiles` and `listDirectory` in `Server/FileOperations.swift` currently pass `.skipsHiddenFiles` to `FileManager.contentsOfDirectory`. Remove that option from both methods so the server always returns all entries. Client-side filtering handles the rest. The `ignoredDirectories` set on the server still excludes `.git`, `node_modules`, etc. The directory watcher's change callback calls `findMarkdownFiles`, so it will automatically include hidden files after this change.

**View layer** — Each window type loads `showHiddenFiles` from storage at creation time:

- `DocumentWindowContent`: loaded in `AppDelegate.openDocument()` and passed as an init parameter (same as `showGutter`, `showSidebar`, etc.)
- `FolderWindowContent`: loaded in `AppDelegate.openFolder()` and passed as an init parameter (same as `showSidebar`)
- `RemoteDocumentWindowContent`: loaded in `.onAppear` (same as `showGutter`, `showGitIndicators`)

All three respond to the `.toggleHiddenFiles` notification by toggling their `@State`, which triggers persistence via `onChange` and updates the tree provider.

**View menu** adds a "Show Hidden Files" item with Cmd+Shift+. shortcut. The `ViewMenuDelegate` reads the current window's persisted state to set the title, same as it does for gutter/line numbers.

### Approach Validation

This mirrors the established per-window settings pattern used throughout the codebase. Sidebar visibility uses this exact flow: global default in PreferencesManager, per-window `@State`, loaded from DocumentSettingsStorage at window creation, persisted on change, toggled via View menu notification. No new patterns are introduced.

### Risks

| Risk                                           | Mitigation                                                                                                          |
|------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| Old remote servers won't return hidden files   | Graceful degradation: no hidden entries in remote sidebars until server binary is redeployed. No error shown.       |
| Cmd+Shift+. conflicts with macOS text input    | Not a standard text input shortcut. Finder uses it for hidden files. macOS does not intercept it in non-Finder apps.|

### Implementation Plan

**Phase 1: Preference and Storage**

- [ ] Add `showHiddenFiles` property to `PreferencesManager` (`src/Preferences/PreferencesManager.swift`) — Bool, default `false`, persisted to UserDefaults key `RedMargin.Preferences.ShowHiddenFiles`
- [ ] Add "Show hidden files" toggle to Preferences > General in a new "Sidebar" section (`src/Preferences/PreferencesView.swift`)
- [ ] Add `saveHiddenFilesVisible`/`loadHiddenFilesVisible` methods to `DocumentSettingsStorage` (`AppMain/DocumentSettingsStorage.swift`) for both `URL` and `RemoteLocation`, following the gutter/git-indicators pattern

**Phase 2: Local File Tree**

- [ ] Add `showHiddenFiles` property to `FileTreeProvider` (`src/Views/FileTreeProvider.swift`) that triggers `refresh()` on change
- [ ] Pass `showHiddenFiles` into `buildTreeRecursive` and conditionally include/exclude `.skipsHiddenFiles` in the `contentsOfDirectory` options
- [ ] Add `showHiddenFiles` init parameter to `DocumentWindowContent` (`AppMain/DocumentView.swift`), defaulting to `PreferencesManager.shared.showHiddenFiles`. Add `@State var showHiddenFiles` initialized from it.
- [ ] Load `showHiddenFiles` from `DocumentSettingsStorage` in `AppDelegate.openDocument()` (`AppMain/AppDelegate.swift`) and pass it to `DocumentWindowContent`
- [ ] Add `showHiddenFiles` init parameter to `FolderWindowContent` (`AppMain/FolderWindowContent.swift`), same pattern. Add `@State var showHiddenFiles` initialized from it.
- [ ] Load `showHiddenFiles` from `DocumentSettingsStorage` in `AppDelegate.openFolder()` (`AppMain/AppDelegateFolderAndMenu.swift`) and pass it to `FolderWindowContent`
- [ ] In both views, add `onChange(of: showHiddenFiles)` to persist via `DocumentSettingsStorage` and update `fileTreeProvider.showHiddenFiles`

**Phase 3: Remote File Tree**

- [ ] Remove `.skipsHiddenFiles` from `findMarkdownFiles` in `Server/FileOperations.swift` (line 60) so the server returns hidden `.md` files
- [ ] Remove `.skipsHiddenFiles` from `listDirectory` in `Server/FileOperations.swift` (line 25) so the server returns hidden directory entries
- [ ] Add `showHiddenFiles` property to `RemoteFileTreeProvider` (`src/Views/RemoteFileTreeProvider.swift`) that triggers `refresh()` on change
- [ ] In `buildTreeRecursive`, skip entries where `entry.name.hasPrefix(".")` unless `showHiddenFiles` is true (after the existing `ignoredDirectories` check)
- [ ] In `convertTrieToNodes`, skip directory names and file names starting with `.` unless `showHiddenFiles` is true
- [ ] Add `@State var showHiddenFiles` to `RemoteDocumentWindowContent` (`AppMain/RemoteDocumentView.swift`), loaded from `DocumentSettingsStorage` in `.onAppear` (same pattern as `showGutter` and `showGitIndicators` at lines 197-201)
- [ ] Add `onChange(of: showHiddenFiles)` to persist via `DocumentSettingsStorage` and update `fileTreeProvider.showHiddenFiles`

**Phase 4: View Menu**

- [ ] Add `.toggleHiddenFiles` notification name to `AppDelegateExtensions.swift`
- [ ] Add `toggleHiddenFiles` action to `AppDelegate` in `AppDelegateFolderAndMenu.swift` — posts the `.toggleHiddenFiles` notification
- [ ] Add "Show Hidden Files" menu item to `createViewMenu` in `MainMenu.swift` with Cmd+Shift+. shortcut and `ViewMenuTag.hiddenFiles` tag, placed after the Sidebar item (before the separator)
- [ ] Update `ViewMenuDelegate.menuNeedsUpdate` in `MainMenu.swift` to read per-window hidden files state from `DocumentSettingsStorage` and set the menu item title, following the same pattern as the gutter/sidebar items
- [ ] Add `@Binding var showHiddenFiles: Bool` to `NotificationModifiers` in `AppMain/DocumentView.swift`, add `.onReceive(.toggleHiddenFiles)` that toggles it, update the call site to pass `$showHiddenFiles`
- [ ] Add `@Binding var showHiddenFiles: Bool` to `FolderNotificationModifiers` in `AppMain/FolderWindowContent.swift`, add `.onReceive(.toggleHiddenFiles)` that toggles it (gate on `checkIsKeyWindow()` only, NOT `hasDocument` — this is a sidebar setting), update the call site to pass `$showHiddenFiles`
- [ ] Add `@Binding var showHiddenFiles: Bool` to `RemoteNotificationModifiers` in `AppMain/RemoteDocumentViewModifiers.swift`, add `.onReceive(.toggleHiddenFiles)` that toggles it, update the call site to pass `$showHiddenFiles`

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one.

### Unit Tests (`Tests/SidebarTests.swift`)

- [ ] `testHiddenFilesExcludedByDefault` - Create a temp directory with `.hidden.md` and `visible.md`, build tree with `showHiddenFiles: false`, assert only `visible.md` appears
- [ ] `testHiddenFilesIncludedWhenEnabled` - Same setup, build tree with `showHiddenFiles: true`, assert both files appear
- [ ] `testHiddenFoldersExcludedByDefault` - Create a temp directory with `.hidden/` containing a `.md` file and `visible/` containing a `.md` file, assert only `visible/` appears
- [ ] `testHiddenFoldersIncludedWhenEnabled` - Same setup with `showHiddenFiles: true`, assert both folders appear
- [ ] `testGitDirectoryAlwaysExcluded` - With `showHiddenFiles: true`, assert `.git/` directory is still excluded
- [ ] `testIgnoredDirectoriesStillExcludedWhenShowingHidden` - With `showHiddenFiles: true`, assert `node_modules/`, `.build/` etc. remain excluded

### Unit Tests (`Tests/PreferencesManagerTests.swift`)

- [ ] `testShowHiddenFilesDefaultsFalse` - Fresh PreferencesManager has `showHiddenFiles == false`
- [ ] `testShowHiddenFilesPersists` - Set to `true`, verify UserDefaults key is written

### Manual Verification (Marco)

- [ ] Open a folder containing hidden subdirectories (e.g., a repo with `.github/`). Confirm sidebar does not show them by default.
- [ ] Press Cmd+Shift+. — confirm hidden folders/files appear in the sidebar immediately.
- [ ] Press Cmd+Shift+. again — confirm they disappear.
- [ ] Open a second window to a different folder. Toggle hidden files in one window only. Confirm each window maintains its own state independently.
- [ ] Close and reopen a window — confirm the hidden files setting is restored.
- [ ] Open Preferences > General — confirm "Show hidden files" checkbox sets the default for new windows.
