# Recent Workspaces

## Meta

- Status: Reviewed
- Branch: feature/recent-workspaces

---

## Business

### Goal

Make returning to recent Redmargin work fast, visible, searchable, and trustworthy for local and remote files and folders.

### Proposal

Add a first-class Recent Workspaces window alongside the existing Open Recent submenu, a toolbar button on every document and folder window that opens it, a Settings-controlled welcome flow on launch when nothing was restored, and a VS Code-style command palette that searches recent workspaces and common app actions.

### Behaviors

User-facing behaviors:

- File > Open Recent stays as a live submenu showing the ten most recent workspaces (pinned and unpinned merged, sorted by last-opened time) with a Clear Menu footer.
- File > Recent Workspaces... opens a searchable Recent Workspaces window.
- The toolbar history button on every document, folder, remote document, and remote folder window opens the same Recent Workspaces window.
- Redmargin shows Recent Workspaces on launch only when no document or folder window was restored from the previous session and Redmargin was not launched by opening a file from Finder, Terminal, or a URL scheme.
- Redmargin shows Recent Workspaces on Dock-icon reopen when no windows are visible.
- A Settings toggle "Show Recent Workspaces at launch" defaults on; turning it off keeps the empty-launch fallback as today's open panel.
- Cmd-P opens the command palette pre-focused on recent workspaces.
- Cmd-Shift-P opens the same command palette pre-focused on app actions.
- Recent Workspaces includes local folders, local files, remote folders, and remote files.
- Opening a local file is recorded as a recent workspace.
- Pinned workspaces stay above ordinary recent workspaces.
- Search matches workspace name, local path, remote host, and remote path.
- Filters show All, Local, and Remote and, independently, All Kinds, Files, and Folders, without changing stored recent workspaces.
- Opening a workspace restores the previous file selection and sidebar state when those saved items are still valid.
- A local workspace that no longer exists is marked Unavailable and offers Remove, Locate..., and Clear Missing.
- A remote workspace that cannot connect stays in the list and offers Try Again and Remove.
- Any workspace row can be removed without opening it.
- Clear All requires confirmation.
- Opening a workspace from the Recent Workspaces window or from the command palette closes that window.
- Locate... for a missing local workspace opens at the last known parent directory of the missing item.

### Acceptance Criteria

- [ ] **A1** File > Recent Workspaces... opens the Recent Workspaces window.
- [ ] **A2** File > Open Recent shows up to ten of the most recent workspaces (pinned and unpinned merged, sorted by last-opened time) with a Clear Menu footer.
- [ ] **A3** The toolbar history button on a local document, local folder, remote document, and remote folder window opens the same Recent Workspaces window as the menu item.
- [ ] **A4** Redmargin shows Recent Workspaces at launch only when no document or folder window was restored, Redmargin was not launched by opening a file (local or via URL scheme), and the "Show Recent Workspaces at launch" setting is on.
- [ ] **A5** Redmargin shows Recent Workspaces on Dock-icon reopen when no windows are visible.
- [ ] **A6** The Settings toggle "Show Recent Workspaces at launch" suppresses the launch-time window when turned off and restores it when turned on.
- [ ] **A7** Cmd-P opens the command palette with the recent workspaces section focused.
- [ ] **A8** Cmd-Shift-P opens the command palette with the app actions section focused.
- [ ] **A9** Local folders, local files, remote folders, and remote files appear in one recent workspace list.
- [ ] **A10** Opening a local file from any open path records the file as a recent workspace.
- [ ] **A11** Pinned workspaces appear above ordinary recent workspaces.
- [ ] **A12** Search narrows recent workspaces by visible name and location.
- [ ] **A13** All, Local, and Remote filters narrow the list without changing stored recents.
- [ ] **A14** All Kinds, Files, and Folders filters narrow the list without changing stored recents.
- [ ] **A15** A user can open a recent workspace with the keyboard or mouse.
- [ ] **A16** A user can remove any single recent workspace without opening it.
- [ ] **A17** A user can clear unavailable local workspaces without removing available or remote workspaces.
- [ ] **A18** Clear All removes recent workspaces only after confirmation.
- [ ] **A19** A missing local workspace is shown as Unavailable instead of failing without explanation.
- [ ] **A20** A failed remote workspace open leaves the workspace in the list with Try Again and Remove choices.
- [ ] **A21** Opening a recent folder restores the previous file selection and sidebar state when those saved items are still valid.
- [ ] **A22** Opening a recent folder still succeeds when its saved file selection no longer exists.
- [ ] **A23** Opening a workspace from the Recent Workspaces window closes that window.
- [ ] **A24** Opening a workspace or running a command from the command palette closes the palette.
- [ ] **A25** Locate... opens the file panel at the last known parent directory of the missing item.

### Out of scope

What is explicitly not part of this work:

- Redesigning the Markdown reading view.
- Changing SSH transport behavior.
- Changing the Open Remote connection sheet beyond using its existing open paths.
- Adding cross-device recent workspace sync.

---

## Technical

### Approach

Create a typed recent-workspace store that replaces the current folder-only recent list while migrating existing folder recents and legacy local or remote recents. The new store represents local files, local folders, remote files, and remote folders; persists pin state and last-opened time; and exposes helper methods for display text, filtering, availability checks, pinning, removing, clearing missing local entries, and opening an item.

Add two UI surfaces backed by the same store and open actions. `RecentWorkspacesWindow` is the full management surface with search, the two independent filter rows (All/Local/Remote and All Kinds/Files/Folders), pinned and recent sections, row actions, missing-local handling, and confirmation for Clear All. `CommandPaletteWindow` is a compact keyboard surface; Cmd-P opens it with the recents section focused and Cmd-Shift-P opens it with the actions section focused. The palette searches recent workspaces plus a fixed app-command catalog wired to the existing `AppDelegate` menu actions and notification-backed commands.

Keep the existing Open Recent submenu but back it with the new store so it shows up to ten most recent workspaces and a Clear Menu footer. Add a sibling `Recent Workspaces...` menu item that opens the window with Shift-Cmd-1. Attach a toolbar history button to Redmargin document, folder, remote document, and remote folder windows. Route Dock-icon reopen with no visible windows to Recent Workspaces. Route launch with no restored windows to Recent Workspaces only when no file was opened from Finder, Terminal, or a URL scheme, and only when the Settings toggle "Show Recent Workspaces at launch" is on; otherwise keep today's open-panel behavior. Add a separate `RecentWorkspacesPolicy` helper so launch decisions are unit-testable away from `AppDelegate`.

### Approach Validation

Mac app conventions surveyed for this design (Xcode, Tower, Sketch, IntelliJ, iA Writer, Nova, Obsidian, Bear) keep File > Open Recent as a standard menu surface alongside any richer welcome surface. This spec follows that pattern: the submenu stays, the new window is additive. Removing the submenu would cost users a two-click muscle-memory path with no offsetting gain.

The Cmd-K shortcut originally proposed conflicts with the universal "Add Link" convention used in Apple Mail, Pages, Notes, and most rich-text and markdown editors. The palette uses VS Code's bindings instead: Cmd-P for files-and-recents focus and Cmd-Shift-P for command focus. The two bindings open the same palette window with different default sections, matching VS Code's Quick Open / Command Palette split that the author already uses daily.

Launch behavior follows the Xcode welcome-window contract: show the window only when Resume restored nothing and the app was not invoked with a file. A Settings toggle ("Show Recent Workspaces at launch") preserves the today-style open-panel fallback for users who prefer it.

Remote workspaces share the list with local ones and use a distinct Remote affordance per row. They are never auto-reopened by the Recent Workspaces flow; reopening uses the existing `restoreRemoteDocuments` path triggered by document state, not by the recents view.

Relevant references:

- [Apple Human Interface Guidelines: Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [Apple Human Interface Guidelines: Menus and actions](https://developer.apple.com/design/human-interface-guidelines/menus-and-actions)
- [Apple Human Interface Guidelines: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [sindresorhus/human-interface-guidelines-extras (Mac default menu items)](https://github.com/sindresorhus/human-interface-guidelines-extras)
- [Xcode welcome window behavior](https://xcode-steps.blogspot.com/2013/08/xcode-4-welcome.html)
- [Tower: Opening Repositories on Mac](https://www.git-tower.com/help/guides/manage-repositories/open-repository/mac)
- [Sketch: Creating, opening and viewing documents](https://www.sketch.com/docs/getting-started/creating-opening-and-viewing-documents/)
- [JetBrains IntelliJ: Open, move, and close projects](https://www.jetbrains.com/help/idea/open-close-and-move-projects.html)
- [VS Code macOS keyboard shortcuts (PDF)](https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf)
- [Mac Resume explained](https://www.themacguys.com/mac-resume-explained-reopen-windows-or-start-fresh/)

### Risks

| Risk | Mitigation |
| --- | --- |
| The new recent store loses existing folder recents | Add migration tests for `RedMargin.RecentFolders`, `RedMargin.RecentDocumentURLs`, `RedMargin.RecentFolderURLs`, and `RedMargin.RecentRemoteLocations`. |
| Missing local entries disappear when a removable drive is disconnected | Availability checks mark local entries as Unavailable in the UI and never remove them unless the user chooses Remove or Clear Missing. |
| Remote items get treated as stale during temporary network failures | Remote opens keep failed items and surface Try Again and Remove; only user removal deletes remote items. Availability check for remote rows is a cached "last result" badge, never a synchronous SSH probe. |
| Command palette grows broad and untestable | Use a fixed `AppCommand` catalog with explicit handlers and unit tests for command availability, search, and dispatch. |
| Toolbar work diverges by window type | Add one toolbar-building helper used by local file, local folder, remote file, and remote folder windows; assert in tests that every window has exactly one history button. |
| Recent files and recent folders compete for the same display name | Rows show a primary name plus a kind chip (File / Folder) and a location line; search matches both. |
| Clear All is triggered accidentally | Require confirmation and keep Remove as the single-row default action. |
| Recent Workspaces window flashes on launch when Resume restores windows | Launch decision lives in a separate `RecentWorkspacesPolicy` helper that takes restored-window counts, file-open intent, and the Settings toggle; unit-tested independently from `AppDelegate`. |
| Opening from Finder/Terminal while welcome window is queued | `applicationDidFinishLaunching` defers the welcome-window decision until after all `application(_:open:)` and `application(_:openFile:)` callbacks have fired and `pendingRemoteLaunches` is drained. |
| Cmd-P shortcut collides with existing Print shortcut | Reassign Print from Cmd-P to Cmd-Option-P. Cmd-P opens the command palette focused on recent workspaces; Cmd-Shift-P opens the same palette focused on app actions. The change is reflected in `MainMenu.swift`, the CHANGELOG, and the README. |
| Toolbar history button steals attention from the title | Use a single `clock.arrow.circlepath` SF Symbol toolbar item, label "Recent Workspaces", aligned on the trailing side of the toolbar with `.automatic` customization. No badge, no tinted background. |

### Implementation Plan

**Phase 1: Recent Workspace Store**

- [ ] **T1** Add `RecentWorkspaceItem`, `RecentWorkspaceKind` (`localFile`, `localFolder`, `remoteFile`, `remoteFolder`), and `RecentWorkspaceLocation` enum (`local(URL)`, `remote(RemoteLocation)`) in `AppMain/RecentWorkspaces.swift`. `RecentWorkspaceItem` is `Codable`, `Hashable`, `Identifiable` with fields `id: UUID`, `kind: RecentWorkspaceKind`, `location: RecentWorkspaceLocation`, `isPinned: Bool`, `lastOpened: Date`, and `lastFailureReason: String?` (nil unless a remote open recently failed). Provide computed `storageKey: String` (`"local:<standardized path>"` or `"remote:<host>:<path>"` — used for de-dup and reference equality, never as the UserDefaults key), `displayTitle: String` (file or folder name), `locationText: String` (parent directory for local, `host:path` for remote), `kindLabel: String` ("File" / "Folder"), and `tierLabel: String` ("Local" / "Remote"). The store NEVER discards an item on read because its target is missing or unreachable; missing-local pruning and remote-availability are UI concerns surfaced via the Unavailable chip, not deletion.
- [ ] **T2** Add `RecentWorkspaceStore` in `AppMain/RecentWorkspaces.swift` as an `ObservableObject` with `@Published var items: [RecentWorkspaceItem]` and methods `add(_:)`, `pin(_:)`, `unpin(_:)`, `remove(_:)`, `clearAll()`, `clearMissingLocal()`, `relocate(_:to:)` (replaces the `location` of one local item and clears its failure state), `markRemoteFailure(_:reason:)`, `clearRemoteFailure(_:)`, `filtered(search:tier:kind:pinnedOnly:)`, plus `pinned: [RecentWorkspaceItem]` and `recent: [RecentWorkspaceItem]` derived getters. Persist to UserDefaults key `RedMargin.RecentWorkspaces` (JSON via `Codable`). On load, if the stored JSON fails to decode, write the raw bytes to `RedMargin.RecentWorkspaces.Corrupt` (overwriting any previous copy), log the failure via `print("[RecentWorkspaceStore] corrupt JSON, recovered to .Corrupt key")`, and start with an empty store rather than crashing. Cap unpinned entries at `AppDelegate.maxRecentItems` (20); pinned entries are uncapped.
- [ ] **T3** Add `RecentWorkspaceMigrator` in `AppMain/RecentWorkspaces.swift` that runs once on first load of `RecentWorkspaceStore`. Reads `RedMargin.RecentFolders` (current `RecentFolderItem` JSON), `RedMargin.RecentDocumentURLs` (legacy file paths), `RedMargin.RecentFolderURLs` (legacy folder paths), and `RedMargin.RecentRemoteLocations` (legacy `[RemoteLocation]`). Maps each to the correct `RecentWorkspaceKind` and merges by `storageKey`, keeping the most recent `lastOpened`. Writes the merged result, then removes only the four legacy keys after a successful save. `RedMargin.RecentRemoteConnections` (recent SSH server names) is left untouched because it backs the Open Remote sheet's server picker.
- [ ] **T4** Update `AppDelegate` (`AppMain/AppDelegate.swift`) to own a single `RecentWorkspaceStore` instance, initialized in `init()`. Remove the `@Published var recentFolderItems` and `loadRecentFolders()`, `saveRecentFolders()`, `pruneRecentFolderItems(_:)`, `recentFolderItemIsValid(_:)`, `loadRecentFolderItems()`, `loadRecentURLs(forKey:)`, `loadLegacyRecentRemoteFolders()`, `addToRecentFolder(_:)`, `addToRecentRemoteFolder(_:)`, `removeRecentFolder(_:)`, `removeRecentRemoteFolder(_:)`, and `clearRecentFolders()` methods, redirecting their callers to the store.
- [ ] **T5** Update local open paths so opening a local file in `AppDelegate.openDocument(_:)` and opening a local folder in `AppDelegateFolderAndMenu.openFolder(_:selectedFile:)` records a `RecentWorkspaceItem` of the correct kind via `store.add(_:)`. Opening from URL-scheme launch and Finder drag both flow through these methods, so no extra hooks are needed.
- [ ] **T6** Update remote open paths so `AppDelegateExtensions.openRemoteDocument(connection:path:)` records `remoteFile` and `openRemoteFolder(connection:path:)` records `remoteFolder`. Trailing-slash normalization for folder paths is preserved.
- [ ] **T7** Preserve selected-file restore for recent folders by keeping `savedSelectedFile(for:)`, `updateFolderWindowFile(folder:to:)`, and `clearSavedSelectedFile(for:)` in `AppMain/AppDelegate.swift`, and the expanded-folder settings stored by `DocumentSettingsStorage.loadExpandedFolders(for:)` keyed by `folderURL.path`. The Recent Workspaces window calls `appDelegate.openFolder(url, selectedFile: appDelegate.savedSelectedFile(for: url))` for local folders and `appDelegate.openRecentRemoteLocation(_:)` for remote folders.
- [ ] **T8** Add open helpers on `AppDelegate`. `openRecentWorkspace(_ item: RecentWorkspaceItem)` dispatches by kind: `localFile` → `openDocument(_:)`; `localFolder` → `openFolder(_:selectedFile:)` passing `savedSelectedFile(for:)`; `remoteFolder` → `openRecentRemoteLocation(_:)` (refactored per next sentence); `remoteFile` → new `openRecentRemoteFile(_:)` that establishes/reuses an SSH connection via `SSHConnectionManager.shared.connection(for:)` and calls `openRemoteDocument(connection:path:)`. Refactor `openRecentRemoteLocation(_:)` so that on remote failure it calls `store.markRemoteFailure(item, reason:)` instead of `removeRecentRemoteFolder(_:)`; no recent-removal happens implicitly. `retryRecentWorkspace(_:)` performs the kind-appropriate open again and on success calls `store.clearRemoteFailure(_:)`. `locateRecentWorkspace(_:)` shows an `NSOpenPanel`, replaces the item's stored location with the chosen path via `store.relocate(_:to:)`, and never removes the item on cancel.

**Phase 2: Recent Workspaces Window — Visual Design**

- [ ] **T9** Add `AppMain/RecentWorkspacesWindow.swift` with a singleton `RecentWorkspacesWindowController` that opens one Recent Workspaces window, focuses and orders front when already open, sets `setFrameAutosaveName("RecentWorkspaces")`, default size 760×560, minimum 600×420, centered on first launch, `styleMask = [.titled, .closable, .miniaturizable, .resizable]`, `tabbingMode = .disallowed`, title "Recent Workspaces". Inject the shared `RecentWorkspaceStore` and the `AppDelegate` reference. The controller exposes a `closeAfterOpening()` method that orders the window out and the `RecentWorkspacesView` calls it after `openRecentWorkspace(_:)`, `retryRecentWorkspace(_:)`, or any Open... / Open Remote... shortcut from the empty state succeeds.
- [ ] **T10** Add `AppMain/RecentWorkspacesView.swift` with the SwiftUI layout: a 56pt header band containing the title "Recent Workspaces" (system font 22pt, semibold) and a trailing 240pt `TextField` with magnifying-glass leading icon and "Search" placeholder, focused on appear; below the header a 36pt filter band with two segmented controls (`All / Local / Remote` and `All Kinds / Files / Folders`) plus a trailing pin-only toggle (`pin.fill` SF Symbol button, on/off); below that a single scrolling list with two pinned sections — `Pinned` (only shown when at least one pinned item exists) and `Recent` — separated by a thin divider; a 44pt footer band with leading `Clear Missing` and `Clear All...` buttons (both subtle), centered selection count when one row is selected, and trailing `Open` primary button (disabled when no selection or selection is missing local). Empty state when the store is empty: centered `clock.arrow.circlepath` SF Symbol (72pt, tertiary color), title "No Recent Workspaces", body "Open a file or folder to start building your recent list.", and two prominent buttons "Open..." and "Open Remote..." wired to `AppDelegate.showOpenPanel` and `AppDelegate.showOpenRemoteSheet`. Empty state for a non-empty store with no matching rows after search/filter: centered `magnifyingglass` SF Symbol (48pt, tertiary), title "No Matches", body "Try a different search or filter.".
- [ ] **T11** Add `AppMain/RecentWorkspaceRowView.swift` rendering one row at 56pt height with 12pt leading/trailing padding: 28pt SF Symbol leading icon (`doc.text` for files, `folder` for folders, with `.fill` variant for pinned) tinted accent color when selected, secondary label otherwise; primary line: `displayTitle` (system 14pt, semibold), kind chip ("File" / "Folder", system 10pt, capsule with quaternary fill), tier chip ("Local" / "Remote", same style), and `Unavailable` chip (red tint) when the local target is missing or the remote item has a recorded failure; secondary line: `locationText` (system 12pt, secondary label, truncated middle with `…`) followed by " · " separator and a relative last-opened time ("Today, 14:32" / "Yesterday" / "2 weeks ago", computed via `RelativeDateTimeFormatter`); trailing area: pin indicator (filled `pin.fill` when pinned, hidden otherwise) and a chevron when the row is in the keyboard-focused state. Row hover and selection use the standard list-row selection background; double-click opens; right-click reveals the context menu (Open, Pin / Unpin, Reveal in Finder when available local, Copy Path, Locate... when missing local, Try Again when remote with failure, Remove).
- [ ] **T12** Implement keyboard behavior in `RecentWorkspacesView`: typing focuses search; Down/Up moves selection across the visible Pinned + Recent rows; Return opens the selected row when usable (no-op with system beep when row is unavailable); Cmd-Return forces re-attempt for remote failures (alias for Try Again); Delete removes the selected row immediately; Cmd-Delete prompts the Clear All confirmation; Tab moves focus search → tier filter → kind filter → pin-only toggle → list → footer Open; Escape clears a non-empty search before closing the window on a second press; Cmd-W closes the window.
- [ ] **T13** Implement missing-local behavior. A local item whose URL fails `FileManager.default.fileExists(atPath:isDirectory:)` (called lazily when the row scrolls into view and cached for the lifetime of the window) renders with the Unavailable chip, Open disabled, and a Locate... action in the context menu and a Locate... button revealed in the trailing row area when hovered. Locate... presents `NSOpenPanel` constrained to the item's expected kind (`canChooseDirectories` true for folders, false for files; `allowedContentTypes` set to the markdown/plainText pair from `AppDelegate.markdownType` for files) with `directoryURL` set to the missing item's URL's `deletingLastPathComponent()`; on selection, the store's item location is replaced via `store.relocate(item, to: pickedURL)` and the Unavailable state clears. Clear Missing removes only unavailable local rows in one shot, with no confirmation.
- [ ] **T14** Implement remote failure behavior. `openRecentRemoteLocation` already raises errors; the Recent Workspaces flow catches them and calls `store.markRemoteFailure(item, reason: error.localizedDescription)`. The row then shows the Unavailable chip with the error message as a tooltip, plus Try Again and Remove actions. Try Again calls `retryRecentWorkspace(_:)`; on success, the failure is cleared.
- [ ] **T15** Implement Clear All confirmation as an `NSAlert` sheet attached to the Recent Workspaces window: messageText "Remove all recent workspaces?", informativeText "Pinned items will also be removed. This cannot be undone.", default button "Remove All" (destructive style on macOS 14+), cancel button "Cancel". Single-row Remove never confirms.
- [ ] **T16** Add accessibility: every row has `.accessibilityLabel("\(displayTitle), \(tierLabel) \(kindLabel.lowercased()), at \(locationText)")`, `.accessibilityValue("Pinned")` when pinned and `.accessibilityValue("Unavailable")` when unavailable, plus `.accessibilityActions` for Open, Pin, Unpin, Remove, Reveal in Finder, Copy Path, Locate, Try Again. Filters expose their selected option via `.accessibilityValue`. The search field is `.accessibilityLabel("Search recent workspaces")`. The window itself sets `NSAccessibility.Notification.titleChanged` when the filter changes.

**Phase 3: Menu, Toolbar, And Launch Policy**

- [ ] **T17** Update the `Open Recent` submenu in `AppMain/MainMenu.swift` so its `RecentFoldersMenuDelegate` (renamed to `OpenRecentMenuDelegate`) reads from `RecentWorkspaceStore`. The submenu shows up to ten most-recently-opened workspaces (pinned and unpinned merged by `lastOpened`), each item titled with `displayTitle`, with `toolTip` set to `locationText`, and a `doc.text` or `folder` SF Symbol leading image (16×16). Items dispatch to `appDelegate.openRecentWorkspace(_:)` via `representedObject = RecentWorkspaceItem`. Below the entries: separator, `Clear Menu` item that calls `store.clearAll()`. Update on every `menuNeedsUpdate(_:)` callback.
- [ ] **T18** Add `File > Recent Workspaces...` menu item in `AppMain/MainMenu.swift` positioned directly below the `Open Recent` submenu, key equivalent `Shift-Cmd-1` (modifier `[.command, .shift]`), wired to `AppDelegate.showRecentWorkspaces(_:)`.
- [ ] **T19** Reassign the Print menu item shortcut in `AppMain/MainMenu.swift` from `Cmd-P` (`keyEquivalent: "p"`, modifier `.command`) to `Cmd-Option-P` (`keyEquivalent: "p"`, modifier `[.command, .option]`). Update title to "Print..." (unchanged). No change to `printDocument(_:)` handler.
- [ ] **T20** Add `File > Command Palette` (Cmd-P, recents focus) and `File > Command Palette — Actions` (Cmd-Shift-P, actions focus) menu items in `AppMain/MainMenu.swift`, both wired to `AppDelegate.showCommandPalette(focus:)`. Place them after `Recent Workspaces...` and before the separator above `Print...`.
- [ ] **T21** Add `AppDelegate.showRecentWorkspaces(_ sender: Any?)` and `AppDelegate.showCommandPalette(focus:)` in `AppMain/AppDelegateFolderAndMenu.swift` (Menu Actions section). Both route to the shared window controllers.
- [ ] **T22** Add `AppMain/WindowToolbar.swift` with a `RedmarginWindowToolbar` class implementing `NSToolbarDelegate`. The toolbar uses identifier `RedmarginWindowToolbar`, displayMode `.iconOnly`, allowsUserCustomization `true`, autosavesConfiguration `true`. Default item set: one `NSToolbarItem` with identifier `recentWorkspaces`, image `clock.arrow.circlepath` SF Symbol, label "Recent Workspaces", paletteLabel "Recent Workspaces", toolTip "Show Recent Workspaces (⇧⌘1)", target `nil` (sends up the responder chain), action `#selector(AppDelegate.showRecentWorkspaces(_:))`. Allowed identifiers add `.flexibleSpace` and `.space` for future use. The class exposes one factory method `install(on window: NSWindow)` that creates the toolbar, sets it on the window, and stores a strong reference on the window via `objc_setAssociatedObject` so the delegate outlives the call.
- [ ] **T23** Update window creation to call `RedmarginWindowToolbar.install(on:)` after each `createWindow(for:rootView:)` in `AppMain/AppDelegate.swift`, each `createFolderWindow(for:rootView:)` in `AppMain/AppDelegateFolderAndMenu.swift`, and each `createRemoteWindow(for:rootView:)` in `AppMain/AppDelegateExtensions.swift`. The toolbar is NOT installed on the Recent Workspaces window, the Command Palette panel, the Preferences window, the Open Remote sheet, or the standard About panel. Existing window sizing, frame autosave names, style mask, and tabbing mode stay unchanged.
- [ ] **T24** Add `AppMain/RecentWorkspacesPolicy.swift` with a pure helper `RecentWorkspacesPolicy.shouldShowAtLaunch(restoredLocalCount:restoredRemoteCount:restoredFolderCount:launchedWithFiles:hasPendingRemoteLaunches:settingEnabled:) -> Bool`. Return `true` only when every restored count is zero, `launchedWithFiles == false`, `hasPendingRemoteLaunches == false`, and `settingEnabled == true`. Unit-test the truth table.
- [ ] **T25** Update `applicationDidFinishLaunching` in `AppMain/AppDelegate.swift` so the existing branch `if savedURLs.isEmpty && savedRemoteLocations.isEmpty && savedFolderURLs.isEmpty && !launchedWithFiles { showOpenPanel() }` becomes: if `RecentWorkspacesPolicy.shouldShowAtLaunch(...)` returns `true` and `PreferencesManager.shared.showRecentWorkspacesAtLaunch` is on, call `showRecentWorkspaces(nil)`; otherwise call `showOpenPanel()` (preserving today's behavior for users who turn the setting off).
- [ ] **T26** Update `applicationShouldHandleReopen` in `AppMain/AppDelegate.swift` so the `if !flag { showOpenPanel() }` branch becomes `if !flag { showRecentWorkspaces(nil) }`. This path is independent of the launch-time Settings toggle.
- [ ] **T27** Add `@Published public var showRecentWorkspacesAtLaunch: Bool` to `PreferencesManager` in `src/Preferences/PreferencesManager.swift` (persisted under `RedMargin.ShowRecentWorkspacesAtLaunch`, default `true`) and surface it in `GeneralSettingsView` in `src/Preferences/PreferencesView.swift` as a `Toggle("Show Recent Workspaces when Redmargin launches with no open windows", isOn: $prefs.showRecentWorkspacesAtLaunch)` placed in a new Section above the Theme/Width Section.
- [ ] **T28** Keep File > Open... and File > Open Remote... unchanged as explicit new-location commands.

**Phase 4: Command Palette**

- [ ] **T29** Add `AppMain/CommandPalette.swift` defining `enum CommandPaletteFocus { case recents, actions }`, `enum AppCommand: CaseIterable, Identifiable` listing every dispatchable command (see T32), and a `CommandPaletteSource` actor that combines `RecentWorkspaceStore.items` and `AppCommand.allCases` into one ranked, filtered list.
- [ ] **T30** Add `AppMain/CommandPaletteWindow.swift` with a singleton `CommandPaletteWindowController` that opens one borderless floating panel: `NSPanel` with `styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = false`, `hidesOnDeactivate = true`, size 640×420 (autosaved as `CommandPalette`), centered horizontally on the active screen with the top edge 22% down the visible frame on first show. The window installs `CommandPaletteView` and accepts an initial `CommandPaletteFocus`.
- [ ] **T31** Add `AppMain/CommandPaletteView.swift`: a single text field with magnifying-glass leading icon, no border, system font 16pt, placeholder "Search workspaces and commands"; below it a scrolling list with two sections, "Recent Workspaces" and "Actions", in the order chosen by `CommandPaletteFocus`. Empty search shows the top six workspaces and all commands grouped under the focused section first. Rows are 40pt with a 22pt SF Symbol icon, primary title, and a trailing secondary muted line for the key equivalent when the command has one. Selected row has the standard list selection background.
- [ ] **T32** Populate `AppCommand` cases for each dispatchable action: `openFile`, `openRemote`, `recentWorkspaces`, `commandPalette`, `commandPaletteActions`, `settings`, `findInPage`, `findNext`, `findPrevious`, `refresh`, `print`, `exportPDF`, `toggleSidebar`, `toggleHiddenFiles`, `toggleGutter`, `toggleLineNumbers`, `toggleGitIndicators`, plus one case per `TextWidth.allCases` value (`textWidth(TextWidth)`) and one per `ContentWidth.allCases` value (`contentWidth(ContentWidth)`), plus `closeWindow`, `minimizeWindow`, `quit`. Each case carries `title`, `keyEquivalent`, `iconName`, `requiresActiveDocument: Bool`, and `handler: (AppDelegate) -> Void` (notification post or selector call matching the existing menu wiring).
- [ ] **T33** Implement palette dispatch in `CommandPaletteView`: Return runs the selected item (opens workspace or invokes command handler); Cmd-Return on a workspace keeps the palette open; Escape closes the palette; Down/Up move selection across visible rows; typing filters using `CommandPaletteSource`. Commands with `requiresActiveDocument == true` are visible but disabled (dim, beep on Return) when no document or folder window is key. Selecting a workspace orders the palette out and calls `AppDelegate.openRecentWorkspace(_:)`. Selecting a command orders the palette out and calls the handler on the next runloop turn (`DispatchQueue.main.async`) so the palette teardown completes before any window manipulation.

**Phase 5: Cleanup And Documentation**

- [ ] **T34** Remove dead code after T4 and T17 land: the `RecentFolderItem` struct in `AppMain/AppDelegate.swift`, the old `loadRecentFolders` / `saveRecentFolders` private helpers, and any reference to `recentFolderItems` outside the new store. The `RecentFoldersMenuDelegate` class is renamed (not deleted) per T17.
- [ ] **T35** Update `README.md` to describe the Recent Workspaces window, the keyboard shortcuts (Shift-Cmd-1, Cmd-P, Cmd-Shift-P), the Print shortcut change to Cmd-Option-P, and the Settings toggle. Update `resources/docs/CHANGELOG.md` under the next unreleased version with a "Recent Workspaces window and command palette; Print shortcut moved to Cmd-Option-P" entry.
- [ ] **T36** Keep all new UI text concise and consistent: "Recent Workspaces", "Command Palette", "Open", "Remove", "Pin", "Unpin", "Locate...", "Try Again", "Clear Missing", "Clear All...", "Unavailable", "File", "Folder", "Local", "Remote", "Search recent workspaces", "Search workspaces and commands".

---

## Testing

Tests are implementation tasks - the implementer writes and passes each one on the dev surface. Numbering continues from the Implementation Plan.

### Unit Tests (`Tests/RecentWorkspacesTests.swift`)

- [ ] **T37** `testRecentWorkspaceItemRoundTripsLocalFile` - A `localFile` item encodes and decodes with title, parent location, pin state, and `lastOpened` intact.
- [ ] **T38** `testRecentWorkspaceItemRoundTripsRemoteFolder` - A `remoteFolder` item encodes and decodes with host, trailing-slash path, kind, pin state, and `lastOpened` intact.
- [ ] **T39** `testRecentWorkspaceStoreMigratesExistingFolderRecents` - Items written by today's `RedMargin.RecentFolders` JSON are read as `localFolder` workspace items and the legacy key is removed after save.
- [ ] **T40** `testRecentWorkspaceStoreMigratesLegacyMixedRecents` - Items written by `RedMargin.RecentDocumentURLs` and `RedMargin.RecentFolderURLs` are read as `localFile` and `localFolder` items respectively and both legacy keys are removed.
- [ ] **T41** `testRecentWorkspaceStoreMigratesLegacyRemoteRecents` - Items written by `RedMargin.RecentRemoteLocations` are read as `remoteFolder` items, the trailing-slash path is preserved, and the legacy key is removed.
- [ ] **T42** `testRecentWorkspaceStoreLeavesRecentRemoteConnectionsAlone` - Migration does not touch `RedMargin.RecentRemoteConnections`.
- [ ] **T43** `testRecentWorkspaceStoreDeduplicatesByStorageKey` - Adding the same item twice keeps a single entry whose `lastOpened` is the most recent.
- [ ] **T44** `testRecentWorkspaceStoreRetainsPinnedEntriesAboveRecents` - Pinned items sort above unpinned in the combined order returned to the view; unpinned items sort by `lastOpened` descending.
- [ ] **T45** `testRecentWorkspaceStoreEnforcesRetentionForUnpinnedEntries` - Adding a 21st unpinned item drops the oldest unpinned entry; pinned entries are never dropped regardless of count.
- [ ] **T46** `testRecentWorkspaceStoreSearchesNameAndLocation` - Filtering by the substring "log" matches a folder named `logs`, a file at `/var/log/notes.md`, a remote host `prod-logs`, and a remote path `/var/log/`.
- [ ] **T47** `testRecentWorkspaceStoreFiltersLocalAndRemote` - The `All`, `Local`, and `Remote` tier filters return the expected partitions for a fixture set.
- [ ] **T48** `testRecentWorkspaceStoreFiltersFilesAndFolders` - The `All Kinds`, `Files`, and `Folders` kind filters return the expected partitions for a fixture set.
- [ ] **T49** `testRecentWorkspaceStorePinOnlyFilter` - The pin-only toggle returns only pinned items regardless of tier and kind selections.
- [ ] **T50** `testClearMissingRemovesOnlyUnavailableLocalEntries` - Clear Missing removes only local items whose URLs no longer exist; available local items and all remote items remain.
- [ ] **T51** `testRemoveDeletesOneWorkspace` - Removing a workspace deletes only the selected item.
- [ ] **T52** `testClearAllRemovesEverything` - Clear All empties the store including pinned entries.
- [ ] **T53** `testMarkRemoteFailurePersistsReasonAndClearsOnRetrySuccess` - `markRemoteFailure(_:reason:)` stores the message on the item's `lastFailureReason`; `clearRemoteFailure(_:)` clears it.
- [ ] **T54** `testRelocateReplacesLocationAndClearsFailure` - `relocate(item, to: newURL)` updates the item's `location` and sets `lastFailureReason` to nil.
- [ ] **T55** `testStoreNeverDropsItemsForMissingTargets` - Items whose local URL no longer exists remain in the store after a reload and are returned by `items`.

### Unit Tests (`Tests/RecentWorkspacesPolicyTests.swift`)

- [ ] **T56** `testPolicyReturnsTrueOnEmptyLaunchWithSettingOn` - Zero restored windows, no launch files, no pending remote launches, setting on → `true`.
- [ ] **T57** `testPolicyReturnsFalseWhenLocalWindowRestored` - At least one restored local window → `false`.
- [ ] **T58** `testPolicyReturnsFalseWhenRemoteWindowRestored` - At least one restored remote window → `false`.
- [ ] **T59** `testPolicyReturnsFalseWhenFolderWindowRestored` - At least one restored folder window → `false`.
- [ ] **T60** `testPolicyReturnsFalseWhenLaunchedWithFiles` - `launchedWithFiles == true` → `false`.
- [ ] **T61** `testPolicyReturnsFalseWhenPendingRemoteLaunches` - `hasPendingRemoteLaunches == true` → `false`.
- [ ] **T62** `testPolicyReturnsFalseWhenSettingOff` - Setting off → `false` even on an otherwise-eligible launch.

### Unit Tests (`Tests/FolderWindowTests.swift`)

- [ ] **T63** `testOpeningLocalFolderRecordsRecentWorkspace` - Calling `appDelegate.openFolder(_:)` records a `localFolder` entry in the store.
- [ ] **T64** `testOpeningLocalFileRecordsRecentWorkspace` - Calling `appDelegate.openDocument(_:)` for a `.md` file records a `localFile` entry in the store.
- [ ] **T65** `testRecentFolderStillRemembersLastSelectedFile` - Opening a recent folder restores the file that `savedSelectedFile(for:)` returns when the file exists.
- [ ] **T66** `testRecentFolderOpensWhenSavedSelectedFileIsMissing` - Opening a recent folder succeeds and shows no document when the saved selected file has been deleted.

### Unit Tests (`Tests/RemoteIntegrationTests.swift`)

- [ ] **T67** `testOpeningRemoteFileRecordsRecentWorkspace` - `openRemoteDocument(connection:path:)` records a `remoteFile` entry.
- [ ] **T68** `testOpeningRemoteFolderRecordsRecentWorkspace` - `openRemoteFolder(connection:path:)` records a `remoteFolder` entry with the trailing slash preserved.
- [ ] **T69** `testFailedRemoteRecentOpenKeepsEntry` - A `retryRecentWorkspace(_:)` that throws leaves the item in the store with a recorded `lastFailureReason`.

### Unit Tests (`Tests/CommandPaletteTests.swift`)

- [ ] **T70** `testCommandPaletteIncludesRecentWorkspaces` - `CommandPaletteSource` returns all recent workspace items from the store.
- [ ] **T71** `testCommandPaletteIncludesAppCommands` - `CommandPaletteSource` includes every `AppCommand.allCases` value.
- [ ] **T72** `testCommandPaletteSearchMatchesRecentAndCommands` - A search for "side" matches the workspace named `Sidebar.md` and the command "Toggle Sidebar".
- [ ] **T73** `testCommandPaletteDispatchesRecentWorkspace` - Activating a workspace row calls `AppDelegate.openRecentWorkspace(_:)` with the matching item.
- [ ] **T74** `testCommandPaletteDispatchesMenuBackedCommand` - Activating "Toggle Sidebar" posts `Notification.Name.toggleSidebar`.
- [ ] **T75** `testCommandPaletteDisablesDocumentOnlyCommandsWithoutDocument` - With no document window key, commands marked `requiresActiveDocument` report `isEnabled == false` and do not dispatch on Return.
- [ ] **T76** `testCommandPaletteRecentsFocusOrdersRecentsFirst` - Opening with `.recents` focus places the Recent Workspaces section above the Actions section.
- [ ] **T77** `testCommandPaletteActionsFocusOrdersActionsFirst` - Opening with `.actions` focus places the Actions section above the Recent Workspaces section.

### Unit Tests (`Tests/PreferencesManagerTests.swift`)

- [ ] **T78** `testShowRecentWorkspacesAtLaunchDefaultsTrue` - With no stored value, `PreferencesManager.shared.showRecentWorkspacesAtLaunch` is `true`.
- [ ] **T79** `testShowRecentWorkspacesAtLaunchRoundTrips` - Setting the property writes to `RedMargin.ShowRecentWorkspacesAtLaunch` and a new `PreferencesManager` instance reads the same value.

### UI Tests (`Tests/UITests/RedmarginUITests/RedmarginUITests/RecentWorkspacesUITests.swift`)

- [ ] **T80** `testRecentWorkspacesWindowOpensFromMenu` - File > Recent Workspaces... opens the Recent Workspaces window; Shift-Cmd-1 opens the same window.
- [ ] **T81** `testRecentWorkspacesWindowOpensFromToolbar` - The toolbar history button on a folder window opens the same Recent Workspaces window.
- [ ] **T82** `testOpenRecentSubmenuShowsTenWorkspaces` - File > Open Recent shows up to ten workspaces and a Clear Menu footer; Clear Menu empties the submenu and the window list together.
- [ ] **T83** `testRecentWorkspacesSearchAndFilters` - Search narrows rows; All/Local/Remote and All Kinds/Files/Folders segmented controls narrow rows independently; the pin-only toggle restricts to pinned.
- [ ] **T84** `testRecentWorkspacesCanRemoveSingleEntry` - A visible row can be removed via Delete key and via context menu without opening it.
- [ ] **T85** `testRecentWorkspacesClearAllRequiresConfirmation` - Clear All... shows an alert sheet; Cancel keeps the list; Remove All empties it.
- [ ] **T86** `testMissingLocalWorkspaceShowsUnavailableState` - A row pointing at a deleted file shows the Unavailable chip, the Open button is disabled, and the context menu offers Locate... and Remove.
- [ ] **T87** `testOpeningWorkspaceClosesRecentWorkspacesWindow` - Pressing Return on a usable row opens the workspace and closes the Recent Workspaces window.
- [ ] **T88** `testCommandPaletteOpensWithCmdP` - Cmd-P opens the command palette with search focused and the Recent Workspaces section first.
- [ ] **T89** `testCommandPaletteOpensWithCmdShiftP` - Cmd-Shift-P opens the same command palette with the Actions section first.
- [ ] **T90** `testCommandPaletteRunsRecentWorkspace` - Selecting a recent workspace from the palette opens it and closes the palette.
- [ ] **T91** `testPrintShortcutIsCmdOptionP` - The File > Print... menu item shows `⌥⌘P` and Cmd-Option-P invokes Print.
- [ ] **T92** `testNoWindowReopenShowsRecentWorkspaces` - Reopening Redmargin via Dock click with no visible windows shows the Recent Workspaces window.
- [ ] **T93** `testLaunchWithRestoredWindowDoesNotShowRecentWorkspaces` - Launching with a restored folder window does not show Recent Workspaces.
- [ ] **T94** `testSettingsToggleSuppressesLaunchWindow` - With the setting off, an otherwise-eligible launch falls back to the open panel and the Recent Workspaces window does not appear.
- [ ] **T95** `testRecentWorkspacesEmptyStateShowsCallToAction` - With no recents, the window shows the empty-state copy with Open... and Open Remote... buttons.

### Build Verification

- [ ] **T96** Run `./resources/scripts/build.sh` and fix every relevant failure until the build passes.
