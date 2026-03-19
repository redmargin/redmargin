# Show Hidden Files in Sidebar

## Meta

- Status: Draft
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
- Per-window state is persisted to UserDefaults (same pattern as gutter, line numbers, git indicators)
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

This follows the same per-window pattern as gutter, line numbers, and git indicators: global default in `PreferencesManager`, per-window `@State` in the view, persisted per-document in `DocumentSettingsStorage`.

**PreferencesManager** gets a new `showHiddenFiles: Bool` property (default `false`), persisted to UserDefaults. This serves as the default for new windows.

**DocumentSettingsStorage** gets `saveHiddenFilesVisible`/`loadHiddenFilesVisible` methods for both local (`URL`) and remote (`RemoteLocation`) documents, following the existing pattern.

**FileTreeProvider** currently passes `.skipsHiddenFiles` to `contentsOfDirectory(at:includingPropertiesForKeys:options:)`. It gains a `showHiddenFiles` property. When true, the `.skipsHiddenFiles` option is removed. Changing the property triggers a refresh.

**RemoteFileTreeProvider** has two code paths: the `findMarkdownFiles` server call and the recursive `listDirectory` fallback. The recursive path filters out dot-prefixed entries unless `showHiddenFiles` is true. The `findMarkdownFiles` path filters dot-prefixed path components in `buildTreeFromPaths`. Same `showHiddenFiles` property with refresh on change.

**View layer** — `DocumentWindowContent`, `FolderWindowContent`, and `RemoteDocumentView` each get a `@State var showHiddenFiles: Bool` initialized from `DocumentSettingsStorage` (falling back to `PreferencesManager.shared.showHiddenFiles`). They respond to the `.toggleHiddenFiles` notification by toggling the state, persisting it, and updating their tree provider's `showHiddenFiles` property (which triggers refresh).

**View menu** adds a "Show Hidden Files" item with Cmd+Shift+. shortcut. The `ViewMenuDelegate` reads the current window's persisted state to set the title, same as it does for gutter/line numbers.

### Approach Validation

This mirrors the established per-window settings pattern used by gutter, line numbers, and git indicators throughout the codebase. Each of those has: a global default in PreferencesManager, per-window `@State`, persistence in DocumentSettingsStorage, a View menu toggle with dynamic title, and a notification-based toggle mechanism. No new patterns are introduced.

### Risks

| Risk                                                          | Mitigation                                                                                                           |
|---------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Remote server `findMarkdownFiles` doesn't return hidden files | Verify the server-side `find` command includes hidden `.md` files. Update `Server/RPCHandler.swift` if it doesn't.   |
| Cmd+Shift+. conflicts with macOS text input                   | Not a standard text input shortcut. Finder uses it for hidden files. macOS does not intercept it in non-Finder apps. |

### Implementation Plan

**Phase 1: Preference and Storage**

- [ ] Add `showHiddenFiles` property to `PreferencesManager` (`src/Preferences/PreferencesManager.swift`) — Bool, default `false`, persisted to UserDefaults key `RedMargin.Preferences.ShowHiddenFiles`
- [ ] Add "Show hidden files" toggle to Preferences > General in a new "Sidebar" section (`src/Preferences/PreferencesView.swift`)
- [ ] Add `saveHiddenFilesVisible`/`loadHiddenFilesVisible` methods to `DocumentSettingsStorage` (`AppMain/DocumentSettingsStorage.swift`) for both `URL` and `RemoteLocation`, following the gutter/git-indicators pattern

**Phase 2: Local File Tree**

- [ ] Add `showHiddenFiles` property to `FileTreeProvider` (`src/Views/FileTreeProvider.swift`) that triggers `refresh()` on change
- [ ] Pass `showHiddenFiles` into `buildTreeRecursive` and conditionally include/exclude `.skipsHiddenFiles` option
- [ ] Add `@State var showHiddenFiles` to `DocumentWindowContent` (`AppMain/DocumentView.swift`), initialized from `DocumentSettingsStorage` falling back to `PreferencesManager.shared.showHiddenFiles`
- [ ] Add `@State var showHiddenFiles` to `FolderWindowContent` (`AppMain/FolderWindowContent.swift`), same initialization pattern
- [ ] Wire up `showHiddenFiles` state to the `FileTreeProvider` instance in both views, persist on change

**Phase 3: Remote File Tree**

- [ ] Add `showHiddenFiles` property to `RemoteFileTreeProvider` (`src/Views/RemoteFileTreeProvider.swift`) that triggers `refresh()` on change
- [ ] Filter hidden entries in `buildTreeRecursive` — skip entries where `entry.name.hasPrefix(".")` unless `showHiddenFiles` is true (still skip `ignoredDirectories`)
- [ ] Filter hidden path components in `buildTreeFromPaths` — skip paths whose components start with `.` unless `showHiddenFiles` is true
- [ ] Add `@State var showHiddenFiles` to `RemoteDocumentView` (`AppMain/RemoteDocumentView.swift`), same initialization pattern using `RemoteLocation` storage
- [ ] Wire up to the `RemoteFileTreeProvider` instance, persist on change
- [ ] Verify the server-side `FindMarkdownFiles` RPC includes hidden `.md` files in its results; update the `find` command if it doesn't (`Server/RPCHandler.swift`)

**Phase 4: View Menu**

- [ ] Add `toggleHiddenFiles` notification to `AppDelegateExtensions.swift`
- [ ] Add `toggleHiddenFiles` action to `AppDelegate` in `AppDelegateFolderAndMenu.swift` — posts the notification
- [ ] Add "Show Hidden Files" menu item to `createViewMenu` in `MainMenu.swift` with Cmd+Shift+. shortcut and `ViewMenuTag.hiddenFiles` tag, placed after the Sidebar item (before the separator)
- [ ] Update `ViewMenuDelegate.menuNeedsUpdate` to read per-window hidden files state from `DocumentSettingsStorage` and set the menu item title accordingly
- [ ] Add `.onReceive` for `.toggleHiddenFiles` notification in `DocumentView`, `FolderWindowContent`, and `RemoteDocumentViewModifiers` — toggle state, persist, update tree provider

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
