# Recent Workspaces

## Meta

- Status: Draft
- Branch: feature/recent-workspaces

---

## Business

### Goal

Make returning to recent Redmargin work fast, visible, searchable, and trustworthy for local and remote files and folders.

### Proposal

Replace the hidden recent submenu with a first-class Recent Workspaces window, a toolbar button that opens it, startup access when no windows are visible, and a keyboard command palette for recent work and common app actions.

### Behaviors

User-facing behaviors:

- File > Recent Workspaces... opens a searchable Recent Workspaces window.
- The toolbar history button opens the same Recent Workspaces window.
- Redmargin shows Recent Workspaces when it starts or reopens with no visible windows.
- Cmd-K opens a compact command palette for recent workspaces and common app actions.
- Recent Workspaces includes local folders, local files, remote folders, and remote files.
- Pinned workspaces stay above ordinary recent workspaces.
- Search matches workspace name, local path, remote host, and remote path.
- Filters show All, Local, and Remote without changing stored recent workspaces.
- Opening a workspace restores the previous file selection and sidebar state when those saved items are still valid.
- A local workspace that no longer exists is marked Unavailable and offers Remove, Locate..., and Clear Missing.
- A remote workspace that cannot connect stays in the list and offers Try Again and Remove.
- Any workspace row can be removed without opening it.
- Clear All requires confirmation.

### Acceptance Criteria

- [ ] **A1** File > Recent Workspaces... opens the Recent Workspaces window.
- [ ] **A2** The toolbar history button opens the same Recent Workspaces window as the menu item.
- [ ] **A3** Redmargin shows Recent Workspaces when it starts or reopens with no visible windows.
- [ ] **A4** Cmd-K opens a command palette that can open recent workspaces and common app actions.
- [ ] **A5** Local folders, local files, remote folders, and remote files appear in one recent workspace list.
- [ ] **A6** Pinned workspaces appear above ordinary recent workspaces.
- [ ] **A7** Search narrows recent workspaces by visible name and location.
- [ ] **A8** All, Local, and Remote filters narrow the list without changing stored recents.
- [ ] **A9** A user can open a recent workspace with the keyboard or mouse.
- [ ] **A10** A user can remove any single recent workspace without opening it.
- [ ] **A11** A user can clear unavailable local workspaces without removing available or remote workspaces.
- [ ] **A12** Clear All removes recent workspaces only after confirmation.
- [ ] **A13** A missing local workspace is shown as Unavailable instead of failing without explanation.
- [ ] **A14** A failed remote workspace open leaves the workspace in the list with Try Again and Remove choices.
- [ ] **A15** Opening a recent folder restores the previous file selection and sidebar state when those saved items are still valid.
- [ ] **A16** Opening a recent folder still succeeds when its saved file selection no longer exists.

### Out of scope

What is explicitly not part of this work:

- Redesigning the Markdown reading view.
- Changing SSH transport behavior.
- Changing the Open Remote connection sheet beyond using its existing open paths.
- Adding cross-device recent workspace sync.

---

## Technical

### Approach

Create a typed recent-workspace store that replaces the current folder-only recent list while migrating existing folder recents and legacy local or remote recents. The new store will represent local files, local folders, remote files, and remote folders; persist pin state and last-opened time; and expose helper methods for display text, filtering, availability checks, pinning, removing, clearing missing local entries, and opening an item.

Add two UI surfaces backed by the same store and open actions. `RecentWorkspacesWindow` is the full management surface with search, filters, pinned and recent sections, row actions, missing-local handling, and confirmation for Clear All. `CommandPaletteWindow` is a compact keyboard surface opened by Cmd-K; it searches recent workspaces plus a fixed app-command catalog wired to the existing `AppDelegate` menu actions and notification-backed commands. Replace the existing Open Recent submenu with a direct Recent Workspaces command, attach a toolbar history button to Redmargin document and folder windows, and route startup/reopen with no visible windows to Recent Workspaces.

### Approach Validation

Apple's menu guidance says submenus should be used sparingly because they hide items and add complexity, which supports replacing a growing recent list submenu with a dedicated surface. Apple's toolbar guidance says every toolbar item should also be available as a menu command, which supports one Recent Workspaces command exposed through both menu and toolbar.

User feedback from VS Code recent-workspace discussions emphasizes folder and workspace return paths, keyboard search, visible recent lists, and predictable restore behavior. JetBrains documentation and support threads show established recent-project patterns that match this design: searchable recent project access, delete-key removal, and command search access to recent projects.

Relevant references:

- [Apple Human Interface Guidelines: Menus](https://developer.apple.com/design/human-interface-guidelines/macos/menus/menu-bar-menus)
- [Apple Human Interface Guidelines: Toolbars](https://developer.apple.com/design/Human-Interface-Guidelines/toolbars)
- [JetBrains Guide: Open recent project](https://www.jetbrains.com/guide/java/tutorials/import-project/open-recent-project/)
- [IntelliJ IDEA Documentation: Recent files and changes](https://www.jetbrains.com/help/idea/recent-files-and-changes.html)
- [VS Code user discussion: Open Recent usefulness](https://www.reddit.com/r/vscode/comments/r3sd4l/how_to_make_open_recent_useful/)
- [VS Code user discussion: Recent files, folders, and workspaces](https://www.reddit.com/r/vscode/comments/hau9eh/recent_files_folders_and_workspaces/)

### Risks

| Risk | Mitigation |
| --- | --- |
| The new recent store loses existing folder recents | Add migration tests for `RedMargin.RecentFolders`, `RedMargin.RecentDocumentURLs`, `RedMargin.RecentFolderURLs`, and `RedMargin.RecentRemoteLocations`. |
| Missing local entries disappear when a removable drive is disconnected | Availability checks mark local entries as Unavailable in the UI and never remove them unless the user chooses Remove or Clear Missing. |
| Remote items get treated as stale during temporary network failures | Remote opens keep failed items and surface Try Again and Remove; only user removal deletes remote items. |
| Cmd-K becomes too broad to test reliably | Use a fixed command catalog with explicit action handlers and unit tests for command availability, search, and dispatch. |
| Toolbar work diverges by window type | Add one toolbar-building helper used by local file, local folder, remote file, and remote folder windows. |
| Recent files and recent folders compete for the same display name | Rows show a primary name plus a location line; search matches both. |
| Clear All is triggered accidentally | Require confirmation and keep Remove as the single-row default action. |

### Implementation Plan

**Phase 1: Recent Workspace Store**

- [ ] **T1** Add `RecentWorkspaceItem` and `RecentWorkspaceKind` in `AppMain/RecentWorkspaces.swift` with codable support for local file, local folder, remote file, remote folder, pin state, last opened date, stable storage key, display title, location text, and local URL or remote location accessors.
- [ ] **T2** Add `RecentWorkspaceStore` in `AppMain/RecentWorkspaces.swift` as an `ObservableObject` that loads, saves, sorts, pins, unpins, removes, clears all, clears unavailable local items, filters by text, filters by All/Local/Remote, and enforces `AppDelegate.maxRecentItems` for unpinned entries.
- [ ] **T3** Migrate existing UserDefaults data from `RedMargin.RecentFolders`, `RedMargin.RecentDocumentURLs`, `RedMargin.RecentFolderURLs`, and `RedMargin.RecentRemoteLocations` into `RedMargin.RecentWorkspaces`, then clear migrated legacy keys after a successful save.
- [ ] **T4** Keep `RedMargin.RecentRemoteConnections` for the Open Remote sheet while adding remote file and folder entries to the new recent workspace store.
- [ ] **T5** Update `AppDelegate` to own one `RecentWorkspaceStore`, expose compatibility methods used by existing callers, and replace `recentFolderItems` reads and writes with recent-workspace store operations.
- [ ] **T6** Update local open paths in `AppMain/AppDelegate.swift` and `AppMain/AppDelegateFolderAndMenu.swift` so opening a local file or local folder records the correct recent workspace kind.
- [ ] **T7** Update remote open paths in `AppMain/AppDelegateExtensions.swift` so opening a remote file or remote folder records the correct recent workspace kind.
- [ ] **T8** Preserve selected-file restore for recent folders by keeping `savedSelectedFile(for:)`, `updateFolderWindowFile(folder:to:)`, and expanded-folder settings keyed by their existing folder path rules.
- [ ] **T9** Add open helpers on `AppDelegate` for `openRecentWorkspace(_:)`, `retryRecentWorkspace(_:)`, and `locateRecentWorkspace(_:)`; local missing entries must not be removed by these helpers unless Remove or Clear Missing is chosen.

**Phase 2: Recent Workspaces Window**

- [ ] **T10** Add `AppMain/RecentWorkspacesWindow.swift` with a reusable window controller that opens one Recent Workspaces window, focuses it when already open, and injects the shared `RecentWorkspaceStore`.
- [ ] **T11** Add `RecentWorkspacesView` with title, search field, All/Local/Remote segmented filter, pinned section, recent section, empty states, and footer actions for Open, Clear Missing, and Clear All.
- [ ] **T12** Add `RecentWorkspaceRowView` showing icon, title, Local or Remote label, location text, last opened text, pinned state, unavailable state, and row actions for Open, Pin or Unpin, Remove, Locate..., Try Again, Reveal in Finder for available local entries, and Copy Location.
- [ ] **T13** Implement keyboard behavior in Recent Workspaces: Return opens the selected usable row, Delete removes the selected row, Escape closes the window, and Tab reaches search, filters, list, and actions.
- [ ] **T14** Implement missing-local behavior in Recent Workspaces: missing local rows display Unavailable, Open is disabled, Locate... updates the stored target, Remove deletes only that row, and Clear Missing removes only unavailable local rows.
- [ ] **T15** Implement remote failure behavior in Recent Workspaces: failed opens display an inline failure message for that row and keep Try Again and Remove available.
- [ ] **T16** Implement Clear All confirmation in Recent Workspaces and keep single-row Remove immediate.
- [ ] **T17** Add accessibility labels and values for row title, kind, location, pin state, unavailable state, and row actions.

**Phase 3: Menu, Toolbar, And Startup Entry Points**

- [ ] **T18** Replace the `Open Recent` submenu in `AppMain/MainMenu.swift` with a direct `Recent Workspaces...` menu item wired to `AppDelegate.showRecentWorkspaces(_:)`.
- [ ] **T19** Add `AppDelegate.showRecentWorkspaces(_:)` and route it to the shared Recent Workspaces window controller.
- [ ] **T20** Add a reusable toolbar builder in `AppMain/WindowToolbar.swift` that installs a history toolbar button on local file, local folder, remote file, and remote folder windows.
- [ ] **T21** Update `createWindow(for:)`, `createFolderWindow(for:)`, and remote window creation to install the shared toolbar without changing existing window sizing or autosave names.
- [ ] **T22** Update `applicationDidFinishLaunching` and `applicationShouldHandleReopen` so no-window startup and reopen show Recent Workspaces instead of the open panel.
- [ ] **T23** Keep File > Open... and File > Open Remote... unchanged as explicit new-location commands.

**Phase 4: Command Palette**

- [ ] **T24** Add `AppMain/CommandPalette.swift` with `CommandPaletteItem`, `CommandPaletteSource`, and a compact window controller opened by `AppDelegate.showCommandPalette(_:)`.
- [ ] **T25** Add a Cmd-K menu item in `AppMain/MainMenu.swift` for `Command Palette...` wired to `AppDelegate.showCommandPalette(_:)`.
- [ ] **T26** Populate the command palette with recent workspace items from `RecentWorkspaceStore`; selecting one calls `openRecentWorkspace(_:)`.
- [ ] **T27** Populate the command palette with app commands for Open, Open Remote, Recent Workspaces, Settings, Find, Refresh, Print, Export PDF, Show or Hide Sidebar, Show or Hide Hidden Files, Show or Hide Gutter, Show or Hide Line Numbers, Show or Hide Git Indicators, Text Width values, Block Width values, Close, and Quit.
- [ ] **T28** Reuse existing AppDelegate actions and NotificationCenter commands for command dispatch so command palette behavior matches menu behavior.
- [ ] **T29** Implement command palette search, keyboard selection, Return to run, Escape to close, and disabled-state handling for actions that need an active document.

**Phase 5: Cleanup And Documentation**

- [ ] **T30** Remove `RecentFoldersMenuDelegate` and any folder-only recent menu code that is no longer used.
- [ ] **T31** Update user-facing references from Open Recent to Recent Workspaces in `README.md` and `resources/docs/CHANGELOG.md`.
- [ ] **T32** Keep all new UI text concise and consistent: Recent Workspaces, Command Palette, Open, Remove, Pin, Unpin, Locate..., Try Again, Clear Missing, Clear All, Unavailable.

---

## Testing

Tests are implementation tasks - the implementer writes and passes each one on the dev surface. Numbering continues from the Implementation Plan.

### Unit Tests (`Tests/RecentWorkspacesTests.swift`)

- [ ] **T33** `testRecentWorkspaceItemRoundTripsLocalFile` - Local file entries encode and decode with title, location, pin state, and last opened date intact.
- [ ] **T34** `testRecentWorkspaceItemRoundTripsRemoteFolder` - Remote folder entries encode and decode with host, path, folder kind, pin state, and last opened date intact.
- [ ] **T35** `testRecentWorkspaceStoreMigratesExistingFolderRecents` - Existing folder recents become local folder workspace entries and legacy keys are cleared after save.
- [ ] **T36** `testRecentWorkspaceStoreMigratesLegacyMixedRecents` - Legacy local file and folder recents become correctly typed workspace entries.
- [ ] **T37** `testRecentWorkspaceStoreMigratesLegacyRemoteRecents` - Legacy remote folder recents become remote folder workspace entries.
- [ ] **T38** `testRecentWorkspaceStoreRetainsPinnedEntriesAboveRecents` - Pinned entries sort above unpinned entries while unpinned entries remain last-opened first.
- [ ] **T39** `testRecentWorkspaceStoreEnforcesRetentionForUnpinnedEntries` - Unpinned entries are capped while pinned entries remain visible.
- [ ] **T40** `testRecentWorkspaceStoreSearchesNameAndLocation` - Search matches workspace display name, local path, remote host, and remote path.
- [ ] **T41** `testRecentWorkspaceStoreFiltersLocalAndRemote` - All, Local, and Remote filters return the expected entries.
- [ ] **T42** `testClearMissingRemovesOnlyUnavailableLocalEntries` - Clear Missing removes missing local entries and keeps available local and remote entries.
- [ ] **T43** `testRemoveDeletesOneWorkspace` - Removing a workspace deletes only the selected item.
- [ ] **T44** `testClearAllRemovesAllWorkspaces` - Clear All empties the store after confirmation is accepted by the test harness.

### Unit Tests (`Tests/FolderWindowTests.swift`)

- [ ] **T45** `testOpeningLocalFolderRecordsRecentWorkspace` - Opening a folder records a local folder workspace entry.
- [ ] **T46** `testOpeningLocalFileRecordsRecentWorkspace` - Opening a standalone file records a local file workspace entry.
- [ ] **T47** `testRecentFolderStillRemembersLastSelectedFile` - A recent folder still restores the saved selected file when the file exists.
- [ ] **T48** `testRecentFolderOpensWhenSavedSelectedFileIsMissing` - A recent folder opens successfully when its saved selected file no longer exists.

### Unit Tests (`Tests/RemoteIntegrationTests.swift`)

- [ ] **T49** `testOpeningRemoteFileRecordsRecentWorkspace` - Opening a remote file records a remote file workspace entry.
- [ ] **T50** `testOpeningRemoteFolderRecordsRecentWorkspace` - Opening a remote folder records a remote folder workspace entry.
- [ ] **T51** `testFailedRemoteRecentOpenKeepsEntry` - A failed remote recent open leaves the entry in the store.

### Unit Tests (`Tests/CommandPaletteTests.swift`)

- [ ] **T52** `testCommandPaletteIncludesRecentWorkspaces` - The palette source includes recent workspace entries from the store.
- [ ] **T53** `testCommandPaletteIncludesAppCommands` - The palette source includes the fixed app command catalog.
- [ ] **T54** `testCommandPaletteSearchMatchesRecentAndCommands` - Search matches recent workspace text and app command text.
- [ ] **T55** `testCommandPaletteDispatchesRecentWorkspace` - Selecting a recent workspace calls the recent workspace open handler.
- [ ] **T56** `testCommandPaletteDispatchesMenuBackedCommand` - Selecting a menu-backed command calls the expected AppDelegate action or notification.
- [ ] **T57** `testCommandPaletteDisablesDocumentOnlyCommandsWithoutDocument` - Document-only commands are disabled when no document window is active.

### UI Tests (`Tests/UITests/RedmarginUITests/RedmarginUITests/RecentWorkspacesUITests.swift`)

- [ ] **T58** `testRecentWorkspacesWindowOpensFromMenu` - File > Recent Workspaces... opens the Recent Workspaces window.
- [ ] **T59** `testRecentWorkspacesWindowOpensFromToolbar` - The toolbar history button opens the same Recent Workspaces window.
- [ ] **T60** `testRecentWorkspacesSearchAndFilters` - Search and All/Local/Remote filters narrow the visible rows.
- [ ] **T61** `testRecentWorkspacesCanRemoveSingleEntry` - A visible row can be removed without opening it.
- [ ] **T62** `testRecentWorkspacesClearAllRequiresConfirmation` - Clear All shows confirmation before removing entries.
- [ ] **T63** `testMissingLocalWorkspaceShowsUnavailableState` - A missing local workspace appears as Unavailable with Remove and Locate... actions.
- [ ] **T64** `testCommandPaletteOpensWithCmdK` - Cmd-K opens the command palette with search focused.
- [ ] **T65** `testCommandPaletteRunsRecentWorkspace` - Selecting a recent workspace from Cmd-K opens it.
- [ ] **T66** `testNoWindowReopenShowsRecentWorkspaces` - Reopening Redmargin with no visible windows shows Recent Workspaces.

### Build Verification

- [ ] **T67** Run `./resources/scripts/build.sh` and fix every relevant failure until the build passes.
