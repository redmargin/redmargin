# Open Folder Support

## Meta
- Status: Draft
- Branch: feature/open-folder

---

## Business

### Problem
Redmargin only opens individual markdown files. To browse between projects (e.g., everything under `~/dev`), you must open a specific file first — the sidebar then derives the folder from that file. There's no way to open a folder directly and browse its markdown files.

### Solution
Allow opening folders via the Open dialog, CLI (`open -a Redmargin ~/dev`), and drag-and-drop. Show the sidebar with a welcome view until a file is selected.

### Behaviors

**Opening a folder:**
- File > Open (Cmd+O) allows selecting both files and folders
- Dropping a folder on the dock icon or app window opens it
- `open -a Redmargin /path/to/folder` opens it
- If the folder is already open, bring that window to front (same as file deduplication)

**Welcome view (no file selected):**
- Sidebar is visible and expanded, rooted at the opened folder
- Content area shows a centered welcome view: Redmargin app icon + "Select a file" subtitle in secondary text
- Window title shows the folder's display path (same format as file windows)
- Print, Export, Find, and gutter/line-number toggles are disabled (no document loaded)

**Selecting a file from sidebar:**
- Welcome view is replaced with the rendered markdown
- Window title updates to the file's display path
- Git gutter, file watching, and all document features activate normally
- Subsequent sidebar clicks navigate between files as usual (existing behavior)

**Persistence:**
- Open folder windows are saved and restored on relaunch (same as file windows)
- Sidebar width and expanded folders persist per folder root path (existing mechanism)
- If a file was selected when the app quit, restore to that file — otherwise restore to welcome view

---

## Technical

### Approach

Add a parallel window type for folders alongside the existing file-based document windows. `AppDelegate` gets a `folderWindows: [URL: NSWindow]` dictionary. A new `FolderWindowContent` SwiftUI view reuses `SidebarSplitView`, `SidebarView`, and `FileTreeProvider` but starts with a welcome view. When a file is clicked, it creates a `DocumentState` and swaps in the `MarkdownWebView`. `FileTreeProvider` gets a second initializer that takes a root directory directly instead of deriving it from a file's git repo.

The open panel changes from `canChooseDirectories = false` to `true` and removes `allowedContentTypes` filtering (so folders aren't grayed out). When a folder URL is selected, `AppDelegate` routes to `openFolder()` instead of `openDocument()`.

### File Changes

**`build/Info.plist`**
- Add `public.folder` to `CFBundleDocumentTypes` so macOS routes folder opens to the app

**`AppMain/AppDelegate.swift`**
- Add `folderWindows: [URL: NSWindow]` dictionary
- Change open panel: set `canChooseDirectories = true`, conditionally clear `allowedContentTypes`
- Route folder URLs from open panel result to new `openFolder(_ url: URL)` method
- `openFolder()`: create `FolderWindowContent`, window, track in `folderWindows`, handle deduplication
- `application(_:open:)` and `openFile()`: detect directories and route to `openFolder()`
- `applicationWillTerminate`: save open folder URLs alongside open file URLs (separate UserDefaults key)
- `applicationDidFinishLaunching`: restore saved folder windows
- `windowWillClose`: clean up `folderWindows` dictionary
- Add `updateFolderWindowTracking(folder:, to fileURL:)` for when a file is selected in a folder window — migrate the window from `folderWindows` to `documentWindows`

**`AppMain/FolderWindowContent.swift`** (new file)
- SwiftUI view with `SidebarSplitView` containing `SidebarView` and content area
- `FileTreeProvider` initialized with root directory (new initializer)
- Content area: `@State private var selectedFileURL: URL?`
  - When nil: show welcome view (app icon + "Select a file")
  - When set: show `MarkdownWebView` with `DocumentState` for the selected file
- `handleFileSelection()`: load file content, create/update `DocumentState`, notify AppDelegate to update window tracking
- Sidebar always visible by default (no toggle needed for initial state)
- Wire up notification modifiers for view toggles, find bar, etc. (reuse existing `NotificationModifiers` pattern)

**`src/Views/FileTreeProvider.swift`**
- Add `init(rootDirectory: URL, expandedFolders: Set<String> = [])` that sets `rootDirectory` directly and builds the tree without git detection
- Keep existing `init(currentFileURL:)` unchanged

**`AppMain/MainMenu.swift`**
- No changes needed — Open menu item already calls `showOpenPanel()` which will be updated

### Risks

| Risk | Mitigation |
|------|------------|
| Open panel with `canChooseDirectories = true` may confuse users expecting only files | Keep `allowedContentTypes` for files so markdown files are still highlighted; folders are naturally selectable alongside them |
| Large folders (e.g., `~/dev` with hundreds of projects) may be slow to enumerate | `FileTreeProvider` already skips `.git`, `node_modules`, `.build`, etc. and only includes directories containing markdown files — this prunes aggressively |
| Transitioning from welcome view to document view in same window may cause flash | Use same fade-in pattern as existing document windows — render hidden, show on content ready |
| Folder window state persistence adds complexity to save/restore | Use separate UserDefaults key (`RedMargin.OpenFolderURLs`) to keep it isolated from file window persistence |

### Implementation Plan

**Phase 1: FileTreeProvider directory initializer**
- [ ] Add `init(rootDirectory: URL, expandedFolders: Set<String> = [])` to `FileTreeProvider`
- [ ] This initializer sets `rootDirectory` directly and calls `buildTree()` + `setupDirectoryWatcher()` without git detection

**Phase 2: FolderWindowContent view**
- [ ] Create `AppMain/FolderWindowContent.swift`
- [ ] Welcome view: centered Redmargin app icon (from `NSApp.applicationIconImage`) + "Select a file" text in `.secondary` color
- [ ] Wire up `SidebarSplitView` with `SidebarView` using the new `FileTreeProvider` init
- [ ] Implement file selection: on click, load file content, create `DocumentState`, swap welcome view for `MarkdownWebView`
- [ ] Wire up notification modifiers (toggles, find bar, print, export) — disable print/export when no file selected
- [ ] Expanded folders persistence (reuse existing `setupExpandedFoldersPersistence` pattern)

**Phase 3: AppDelegate folder support**
- [ ] Add `folderWindows` dictionary and `openFolder(_ url: URL)` method
- [ ] Modify open panel: `canChooseDirectories = true`, detect folder selection and route to `openFolder()`
- [ ] Handle folder URLs in `application(_:open:)` and `openFile()`
- [ ] `windowWillClose`: clean up `folderWindows`
- [ ] `updateFolderWindowTracking()` for migrating folder window to document window on file selection

**Phase 4: Persistence and Info.plist**
- [ ] Add `public.folder` to `CFBundleDocumentTypes` in `build/Info.plist`
- [ ] Save/restore open folder URLs on quit/launch (separate UserDefaults key)
- [ ] Track which file was selected in a folder window so it can be restored

---

## Testing

Tests in `Tests/`. Results logged in `Tests/TEST_LOG.md`.

### Unit Tests (`Tests/FileTreeProviderTests.swift`)

- [ ] `testDirectoryInitializer` - FileTreeProvider initialized with root directory sets rootDirectory and builds tree without git detection
- [ ] `testDirectoryInitializerExcludesIgnored` - Ignored directories (.git, node_modules, etc.) are excluded when using directory initializer
- [ ] `testDirectoryInitializerOnlyMarkdown` - Only .md and .markdown files appear in tree from directory initializer

### Integration Tests

- [ ] `testOpenFolderCreatesWindow` - Calling `openFolder()` creates a window tracked in `folderWindows`
- [ ] `testOpenFolderDeduplication` - Opening the same folder twice brings existing window to front
- [ ] `testFolderDetectionInOpenURLs` - Directory URLs passed to `application(_:open:)` route to `openFolder()`

### Manual Verification (Marco)

- [ ] Open a folder via File > Open — sidebar shows markdown files, content area shows welcome view with app icon
- [ ] Click a file in sidebar — markdown renders, window title updates
- [ ] `open -a Redmargin ~/dev` from Terminal opens folder window
- [ ] Drop a folder on dock icon — opens folder window
- [ ] Quit and relaunch — folder window restores (with or without selected file)
