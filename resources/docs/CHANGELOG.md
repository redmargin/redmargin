# Changelog
<!-- markdownlint-disable MD022 MD032 -->

## v1.4.0 (2026-05-28)

### New Features

- Installed `redmargin` command opens local files/folders and remote SSH paths in the running app without replacing existing windows
- Recent Workspaces window and command palette; Print shortcut moved to Cmd-Option-P
- Mermaid fenced code blocks now render as diagrams in the preview, with copy-source buttons and source-mapped gutter/line-number support
- Mermaid diagrams rerender for light/dark theme changes and are preserved in print preview and PDF export
- Print and PDF export now share configurable top, right, bottom, and left margins plus a base font size in Preferences > Print & Export
- Sidebar file rows now show git status indicators for modified, staged, untracked, and conflicted files, with a default-on Preferences toggle

### Security

- Mermaid SVG output is sanitized before insertion, and invalid or unavailable Mermaid renders now fall back to the original source with an error banner instead of blank output

### Bug Fixes

- Open Recent now restores folder windows with the selected file focused correctly
- Settings number fields now commit edited values before tab navigation changes focus
- Print preview now forces Mermaid blocks onto the light print palette even when printing from dark mode
- Preferences window can now be resized taller so every setting remains reachable
- Line numbers and git gutter now prefer the most specific source-mapped elements, preventing duplicate list numbers and oversized list/table change markers

---

## v1.3.0 (2026-03-19)

### New Features

- Show/hide hidden files in sidebar (Cmd+Shift+.) — per-window toggle with global default in Preferences
- Lazy sidebar loading: folders enumerate one level at a time, children load on expand — instant even for large directories
- All folders shown in sidebar regardless of markdown content
- Symlinked directories resolve and expand correctly
- Copy-to-clipboard button on code blocks
- Configurable content width: separate Text Width (Narrow/Medium/Wide/Unrestricted) and Content Width (Medium/Wide/Unrestricted) preferences in General > Appearance
- Tables and code blocks default to unrestricted width while prose stays readable at 680px
- YAML front matter renders as a styled metadata card above the document instead of raw text
- Open remote folders as workspaces via the "Open Folder" button in the Open Remote sheet
- Recent files menu now organized into labeled sections: Documents, Remote Documents, and Folders

### Improvements

- Sidebar file selections now tracked in Recent Documents
- Recent Documents limit increased from 10 to 20
- Tables reflow when window is resized (no longer stuck at initial render width)
- Table width calculation accounts for container padding, preventing overflow into right margin
- Checkbox clicks only toggle on direct checkbox clicks, not when clicking surrounding text or selecting text nearby
- Front matter tags/categories render as pill chips, dates are locale-formatted, draft status shows a badge
- Git gutter and line numbers stay aligned when front matter is present (sourcepos offset applied)

### Bug Fixes

- Fixed scroll position not restoring after relaunch
- Fixed infinite refresh cycles and unreliable refresh for remote machines
- Fixed SSH reconnection failures and stale connection detection
- Fixed Linux server build (os.log unavailable on Linux)

## v1.2.0 (2026-02-23)

### New Features
- Open folders directly via File > Open, drag-and-drop, or `open -a Redmargin ~/path/to/folder`
- Folder windows show sidebar with markdown file tree and a welcome view until a file is selected
- Folder windows persist and restore on relaunch (including selected file, sidebar width, and sidebar visibility)
- Sidebar file list now auto-updates when files are added, removed, or renamed (local and remote)
- Cmd-R now refreshes both document content and sidebar file list when sidebar is visible
- Checkboxes in markdown tables: `[ ]` and `[x]` in table cells render as interactive checkboxes

### Improvements
- Migrated DocumentState and RemoteDocumentState from ObservableObject to @Observable for more precise SwiftUI view updates
- Remote file watcher now survives vim-style atomic saves (server-side inotify retry with exponential backoff)
- Remote Cmd-R now properly busts image cache (refreshToken wired through to MarkdownWebView)
- Local sidebar uses FSEvents for recursive directory monitoring (single kernel-level watcher for entire tree)
- Remote sidebar uses server-pushed file lists on directory changes (zero SSH calls after initial setup)

### Bug Fixes
- Fixed remote refresh (Cmd-R) hanging with infinite spinner when SSH connection goes stale after idle
- Fixed remote documents auto-recovering after SSH disconnect (no Cmd-R needed; reconnects and refreshes automatically)
- Fixed stale SSH connections detected proactively: idle connections are pinged before refresh or file load to avoid 30s hangs
- Fixed remote documents not reconnecting after Mac wakes from sleep (forced SSH reconnection on wake)
- Fixed false "Reconnecting" flashes when remote files change (serialized stdin writes prevent pipe contention from triggering disconnect)
- Fixed remote refresh() silently swallowing errors (now logs failures explicitly)
- Fixed flaky sidebar tests caused by race conditions with async file tree loading
- Fixed search not working in folder windows
- Fixed sidebar expansion state not persisting across relaunch
- Fixed sidebar scroll position lost during file tree refresh
- Fixed sidebar beachball caused by tree build on main thread
- Fixed sidebar file selection showing wrong file content
- Fixed file watcher dying permanently and folder selection freezing

---

## v1.1.0 (2026-02-08)

### Improvements
- Table column widths now intelligently sized using min-content/max-content measurement (no mid-word breaks, short columns stay tight, long columns get proportional space)
- Remote file list refresh now uses single RPC call instead of one per directory
- Remote file open faster: batched server deployment checks, cached git repo detection, parallelized init

### Bug Fixes
- Fixed remote documents failing to restore on app relaunch (SSH connections now retry with delays and share connections per host)
- Fixed sidebar refresh button being too small and conflicting with divider hit target
- Fixed PDF export and print using wrong filename for remote files
- Fixed checkbox color changing to white when window loses focus
- Fixed crash during SSH reconnection caused by race condition between file handle callbacks and process termination
- Fixed frontmost window not preserving on relaunch

---

## v1.0.2 (2026-01-27)

### Bug Fixes
- Images now load correctly when navigating between documents via sidebar

### Improvements
- README updated with clearer feature descriptions and accurate theme options

---

## v1.0.1 (2026-01-27)

### Bug Fixes
- Remote sidebar refresh button now shows loading indicator during refresh

### Improvements
- GitHub release workflow now auto-generates release notes from changelog

---

## v1.0.0 (2026-01-26)

First stable release.

### Syntax Highlighting
- Code blocks with language specifiers render with syntax coloring via highlight.js
- Supports Python, JavaScript, TypeScript, Swift, Rust, Go, Java, Bash, JSON, YAML, SQL, HTML, CSS, Markdown, and more
- Theme-aware: light and dark themes have matching color schemes
- Unsupported languages fall back gracefully to plain monospace

### File Sidebar
- Browse Markdown files in your Git repo without leaving the app (Cmd+1 to toggle)
- Falls back to file's directory when not in a Git repo
- Hierarchical folder tree with collapsible directories
- Current file highlighted, click to navigate within the same window
- Works for both local and remote documents
- Auto-refreshes when files are added or removed
- Folder expansion state persists across app restarts
- Window resizes to keep document area constant when toggling

### Per-Document View Settings
- Gutter, line numbers, and git indicator visibility saved per file
- View menu dynamically shows "Show/Hide" based on current document state
- Sidebar visibility and width saved per document

### Other Changes
- About dialog updated with full feature description
- Version bumped to 1.0.0 across app, server, and documentation

---

## v0.78.0 (2026-01-25)

### File Sidebar
- Sidebar shows Markdown files from Git repo root (Cmd+1 to toggle)
- Click files to navigate within the same window
- Works for both local and remote documents
- Collapsible folders with current file highlighted
- Refresh button to update file list
- Window resizes to keep document area constant when toggling sidebar
- Sidebar state persists correctly after same-window navigation and app restart

### View Menu Improvements
- Per-document gutter, line numbers, and git indicators settings
- View menu shows "Show/Hide" based on current document state
- Keyboard shortcuts: Cmd+Option+G (Gutter), Cmd+L (Line Numbers), Cmd+Shift+I (Git Indicators)
- Settings in Preferences now set defaults for new documents
- Removed "Enter Full Screen" menu item

---

## v0.77.1 (2026-01-24)

### Remote Files via SSH
- View Markdown files on remote servers via SSH (Cmd+Shift+O)
- File browser with path navigation, keyboard controls (arrow keys, Enter)
- Remote images load automatically with in-memory caching
- Interactive checkboxes sync back to remote files
- Remote documents appear in File > Open Recent
- Automatic server deployment - daemon binary uploaded on first connect
- Connection resilience with auto-reconnect and conflict resolution
- Supports both Linux and macOS remote hosts

### PDF Export
- Export to PDF (Cmd+E) saves directly to Downloads folder
- Preserves current theme (light or dark) in exported PDF
- Includes Git gutter markers, red margin line, and line numbers
- Unique filename generation prevents overwrites (document.pdf, document-1.pdf, etc.)
- Progress indicator during export

### Rendering Improvements
- Anchor links scroll smoothly to heading targets
- Image refresh with Cmd+R (cache-busting for updated images)
- No more white flash when opening documents in dark mode

### Fixes
- File open dialog now opens instantly
- Documents passed via command line appear on top of restored windows
- Remote checkbox toggles no longer revert due to race conditions
- SSH connections no longer hang on authentication failures

---

## 260124 Export to PDF
- Added: Export as PDF (Cmd+E) saves directly to Downloads without print dialog
- Added: Dark theme preserved in exported PDFs
- Added: Unique filename generation (document.pdf, document-1.pdf, etc.)
- Added: Progress indicator during export
- Changed: PDF export now shows gutter (git bars, red margin) and line numbers
- Note: Known WebKit limitation causes thin white line at top of pages in dark theme

## 260124 Remote Document Improvements
- Added: Remote image loading via WKURLSchemeHandler (redmargin-remote:// scheme)
- Added: ReadAsset RPC for fetching binary assets over SSH
- Added: In-memory asset cache to prevent re-fetching on view updates
- Added: Remote document restoration on app relaunch
- Added: Keyboard navigation for file browser entries (up/down arrows, Enter)
- Changed: File browser defaults to /opt instead of home directory
- Changed: ReadAsset timeout increased to 60s for large files
- Fixed: ".." entry now shown on first directory listing (not just after navigation)

## 260120 Image Refresh and Window Flash Fix
- Fixed: Image refresh now works with Cmd+R (cache-bust query param on local images)
- Fixed: White flash when opening documents in dark mode
- Added: Window fades in after content renders (prevents seeing unthemed content)
- Added: Theme detection via prefers-color-scheme loads correct stylesheet immediately

## 260120 ServerTests Added
- Added: Tests/ServerTests.swift with daemon lifecycle tests
- Added: testDaemonStartStop verifies PID file, socket, RPC handshake
- Added: testDaemonSurvivesProxyDisconnect verifies reconnection works
- Changed: testFileWatchPushEvent skipped (requires main run loop on macOS)
- Updated: Spec test checkboxes marked complete

## 260120 Remote Recents Bug Fixes
- Fixed: Remote files from Recents now work (was timing out on stale connections)
- Fixed: Deleted remote files are now removed from Recents menu
- Added: Quick SSH check before opening remote file for instant feedback
- Added: Structured error codes (FILE_NOT_FOUND) instead of text matching
- Changed: SSHConnectionManager validates process health before reusing connections

## 260120 Remote Checkbox and File Safety
- Fixed: Remote checkbox toggle now works reliably (was reverting due to race condition)
- Fixed: Server writeFile uses POSIX rename() to prevent file deletion on Linux
- Fixed: Reload task cancellation prevents stale reads from overwriting checkbox changes
- Changed: Removed FileManager.replaceItemAt which has known issues on Linux

## 260120 Anchor Links
- Added: Heading anchor plugin for internal link navigation (headingAnchors.js)
- Fixed: Anchor links now scroll smoothly to target sections
- Fixed: Fragment ID escaping in navigation handler

## 260120 Code Quality: Fix Lint Violations
- Fixed: SSHConnection type body length by extracting types and helpers to separate files
- Fixed: AppDelegate type body length by extracting extensions to separate file
- Added: SSHConnectionTypes.swift (state enum, error enum, StderrCollector)
- Added: SSHConnectionHelpers.swift (SyncMarkerAccumulator, parseSSHStderr)
- Added: AppDelegateExtensions.swift (Notification.Name, URL extension, remote methods)
- Changed: swiftlint.yml thresholds adjusted (type_body: 400, file: 600)
- Improved: Test file now contains 11k lines of proper markdown content

## 260120 Phase 9: Checkbox Caching and Remote Recents
- Added: Checkbox toggles cached during disconnect, restored on reconnect
- Added: Conflict resolution dialog when remote file changes during disconnect
- Added: Remote files now appear in File > Open Recent menu
- Added: Connection state streaming for real-time UI updates
- Changed: Spec status updated to Implementation Complete

## 260120 SSH First-Connection Fix (v0.42.10)
- Fixed: SSH remote connections now work on first attempt (was failing, then working on retry)
- Fixed: process.waitUntilExit() hanging with GCD on Linux - replaced with usleep()
- Fixed: Thread.sleep() in connect loop replaced with usleep() to avoid GCD issues
- Changed: Sync marker output simplified (removed RDY handshake complexity)
- Changed: UnixSocketListener print() changed to fputs(stderr) to prevent protocol corruption

## 260120 SSH Remote File Improvements
- Added: Path input field in file browser for navigating to any path (not just home)
- Added: Delete button (minus icon) to remove servers from recent list
- Added: Connection status messages during connect (Checking server / Deploying / Connecting)
- Added: Auto-retry with redeploy when server handshake fails
- Changed: Window title now shows server name and full path: `[hostname] /path/to/file`
- Changed: Path field auto-focused when server connects
- Changed: Server binary stdout/stderr redirected to prevent RPC corruption
- Changed: SSH ControlMaster disabled to prevent stale socket issues
- Changed: Build script now force-kills app if graceful quit fails
- Fixed: "Session open refused by peer" errors from stale SSH control sockets
- Fixed: Old daemon processes now killed when deploying new server version
- Fixed: Daemon/Proxy print statements moved to stderr to prevent protocol corruption

## 260120 SSH Connection Timeout & Error Handling
- Added: SSHConnectionError enum with user-friendly error messages
- Added: Timeout on all SSH operations (30s overall connection, 15s handshake, 30s operations)
- Added: Stderr monitoring to detect and report SSH failures (auth, refused, unreachable)
- Added: Early failure detection (200ms check after SSH process starts)
- Changed: ControlPath moved to /tmp for reliable path expansion
- Changed: SSH options now include ServerAliveInterval/ServerAliveCountMax for keepalives
- Changed: ControlPersist=60 for connection reuse
- Fixed: SSH connections no longer hang indefinitely on failure

## 260120 Phase 8: Remote File UI Integration
- Added: "Open Remote..." menu item (Cmd+Shift+O) for connecting to SSH servers
- Added: OpenRemoteSheet for entering connection strings (user@host:/path format)
- Added: RemoteDocumentView for viewing remote files with connection status
- Added: Recent remote connections stored in UserDefaults
- Added: RemoteConnectionParser for parsing SSH connection strings
- Added: RemoteLocation type for representing remote file locations
- Added: LocalFileProviderTests with comprehensive test coverage
- Added: RemoteUITests for connection string parsing and RemoteLocation
- Changed: ServerDeployer now supports macOS servers (Darwin detection)
- Changed: ServerDeployer cleans up old version binaries on upgrade
- Changed: Build script fixed for proper quoting
- Updated: CLAUDE.local.md with devtest server info and timeout guidance

## 260119 Phase 6: Remote File Provider and Server Deployment
- Added: RemoteFileProvider for reading/writing files over SSH connections
- Added: ServerDeployer for uploading daemon binary to remote hosts
- Added: Linux build scripts (build-linux.sh, build-remote.sh) for cross-compilation
- Added: FileProvider protocol abstraction for local vs remote file operations
- Added: SSHConnectionManager tests for connection multiplexing
- Changed: DocumentState now supports remote file providers
- Changed: ProcessRunner improved for remote command execution
- Changed: Build script updated for multi-platform support

## 260114 Command-Line File Focus
- Fixed: File passed via command line now appears on top of restored documents

## 260113 Document Restoration Fix
- Fixed: `open -a Redmargin file.md` now restores previously open documents instead of forgetting them

## 260113 Documentation Cleanup
- Changed: Renamed `resources/redmargin_icon_pack` to `resources/icons`
- Changed: Updated README project structure to reflect actual codebase
- Changed: README status now shows version number
- Removed: RedMargin_IconPack.zip (redundant with unpacked icons folder)
- Removed: scratch.md from git history
- Fixed: Package.swift warning for unhandled test script

## 260113 File Dialog Improvements
- Fixed: File open dialog now opens instantly (reuse panel, pre-initialize at launch)
- Changed: File open dialog now uses async presentation for better responsiveness
- Changed: Dialog opens as sheet when a window is active, standalone otherwise
- Changed: Default window size increased to 950x1100 to fit content width
- Fixed: Sluggish file dialog behavior with Default Folder X
- Added: File dialog is now resizable

## 260112 Settings Window Refactor (v0.42.0)
- Changed: Settings window now uses pure AppKit (NSWindowController) instead of SwiftUI Settings scene
- Fixed: Removed unwanted sidebar toggle button from settings window
- Fixed: Removed empty window appearing on app launch
- Changed: Print margin uses NumberTextField with arrow key support for increment/decrement
- Changed: Menus rebuilt in AppKit for cleaner integration

## 260112 Stage 10: Print Support
- Added: Print support (Cmd+P) opens macOS print dialog directly
- Added: Print settings in Preferences > Print tab: gutter markers, line numbers, margin
- Added: Resizable preferences window with sidebar navigation (General, Print tabs)
- Added: Print-friendly CSS for tables (light headers, borders) and code blocks
- Added: PDF filename uses original document name instead of "RedmarginRender"
- Added: Always uses light theme for print output
- Changed: Preferences window uses NavigationSplitView with column width constraints
- Removed: Header/footer feature descoped (WKWebView limitation documented in spec)

## 260111 Stage 9: Preferences
- Added: Preferences window (Cmd+,) with theme, inline code color, gutter, and remote images settings
- Added: PreferencesManager singleton with UserDefaults persistence
- Added: PreferencesView SwiftUI form with pickers and toggles
- Added: Theme selection: System (follows macOS), Light, Dark
- Added: Inline code color presets: Warm, Cool, Rose, Purple, Neutral
- Added: Gutter visibility option for non-repository files: Show empty / Hide
- Added: Remote images toggle (blocked by default for security)
- Added: 5 unit tests for PreferencesManager persistence
- Changed: WebView now receives theme and preferences from DocumentWindowContent
- Changed: JS renderer supports runtime theme and inline code color switching

## 260111 Stage 8: Find in Page
- Added: Find bar with search text field, match count, and navigation buttons
- Added: FindController class for managing find operations via JavaScript window.find()
- Added: Edit menu with Find... (Cmd+F), Find Next (Cmd+G), Find Previous (Cmd+Shift+G)
- Added: Escape key dismisses find bar, Cmd+F refocuses when already open
- Added: 5 unit tests for find functionality (FindTests.swift)
- Changed: Edit menu cleaned up - removed Undo/Redo/Cut/Paste, kept Copy/Select All
- Changed: Find jumps to first match and stays there while typing

## 260111 Stage 7: Git State Watching
- Added: HEAD watcher detects branch switches and updates gutter
- Added: Branch ref watcher detects commits and clears gutter for committed lines
- Added: 5 unit tests for git state watching (GitStateWatcherTests.swift)
- Changed: Stage 7 spec marked complete with simplified implementation notes

## 260111 Git Gutter Stability Fixes
- Fixed: Git change detection race condition - cancels stale async tasks
- Fixed: Scroll position preserved when toggling line numbers
- Fixed: File watcher race condition on atomic saves (close fd before reopening)
- Fixed: Git index watcher no longer loops on .attrib events (writeOnly mode)
- Fixed: RAF stale closure issue in JS gutter updates
- Added: 4 JS unit tests for gutter markers
- Added: 3 Swift unit tests for gutter integration
- Changed: DocumentWindowContent uses @StateObject for stable state

## 260111 Line Numbers & WebRenderer
- Added: WebRenderer source files now version controlled (was in .gitignore)
- Added: Line numbers show ALL source lines including blank lines via gap interpolation
- Added: 6 JS tests for line number gap-filling and offset alignment
- Added: /run-tests command for project-specific test workflow
- Changed: WKWebView uses non-persistent storage (fixes JS caching between sessions)
- Fixed: Line number vertical alignment - 3px offset for text, 8px extra for table rows

## 260110 Stage 5: Git Gutter
- Added: Git gutter markers showing changed/added/deleted lines in WebView
- Added: SourcePosMap - maps source lines to DOM elements via data-sourcepos
- Added: Gutter.js - renders colored markers, handles scroll/resize
- Added: gutter.css with marker styles and theme color variables
- Added: 17 JS unit tests for sourcepos mapping and overlap logic
- Changed: GitChangeResult now separates addedRanges, modifiedRanges, deletedAnchors
- Changed: Cmd-L now hides only line numbers, not the entire gutter
- Fixed: Scroll position preserved when file changes externally
- Fixed: ProcessRunner now uses async termination handler (was blocking main thread)
- Fixed: FileWatcher now handles atomic writes by restarting after rename/delete events

## 260110 Stage 4: Git Diff Parsing
- Added: DiffHunk - parses unified diff hunk headers (@@ -old,count +new,count @@)
- Added: GitChangeResult - struct with changedRanges, deletedAnchors, isUntracked
- Added: GitDiffParser - runs git diff and parses output to line ranges
- Added: Untracked file detection via git ls-files
- Added: FixtureLoader helper for loading test fixtures from files
- Added: 6 diff fixture files (addition, deletion, modification, multiple-hunks, empty, binary)
- Added: 24 unit tests for DiffHunk parsing and fixture loading
- Added: 10 integration tests with real git repos
- Fixed: File watcher now properly updates view when source file changes externally

## 260110 Stage 3: Git Repo Detection
- Added: GitRepoDetector - detects if file is in a Git repo and finds repo root
- Added: ProcessRunner - async wrapper around Process for shell commands
- Added: GitError enum for Git-related error handling
- Added: GitTestHelper for creating temp Git repos in tests
- Added: 8 GitRepoDetector tests (repo root, subdirectory, submodule, worktree, spaces, unicode)
- Added: 6 ProcessRunner tests (stdout, stderr, exit code, working directory)
- Changed: Package structure split into RedmarginLib + Redmargin executable for testability

## 260110 Per-Document Settings & Build Improvements
- Added: Per-file line numbers toggle (each document remembers its setting)
- Added: Local image support in markdown files
- Added: Inline code color preference to Stage 9 spec
- Changed: App renamed from RedMargin to Redmargin
- Changed: Build now uses release configuration (smaller/faster binary)
- Changed: Build installs directly to /Applications (no duplicate in build/)

## 260110 Interactive Features & Polish
- Added: Interactive checkboxes - click to toggle task items, saves immediately
- Added: Line numbers in gutter showing source line mapping
- Added: App icon from RedMargin icon pack
- Added: Window z-order preservation on app relaunch
- Added: Scroll position persistence per document

## 260110 WebView Renderer & App Shell Refinements
- Added: WKWebView-based Markdown rendering with markdown-it
- Added: Sourcepos plugin for line mapping (data-sourcepos attributes)
- Added: Light/dark CSS themes following system appearance
- Added: State restoration - open documents saved on quit, restored on relaunch
- Added: Custom recent documents tracking (File > Open Recent)
- Changed: Architecture from DocumentGroup to Settings scene + manual NSWindow
- Changed: Launch behavior now follows Preview.app pattern:
  - First launch: Show Open panel
  - Relaunch with saved state: Restore previous documents
  - Dock click with no windows: Show Open panel
- Fixed: Window size/position persistence per document

## 260110 App Shell Implementation
- Added: SwiftUI document-based app structure (Package.swift, RedMarginApp.swift)
- Added: MarkdownDocument conforming to FileDocument for .md/.markdown files
- Added: DocumentView with signature red margin line and paper-like background
- Added: Light/dark theme support with refined typography
- Added: App bundle with stable bundle ID (com.redmargin.app) for consistent permissions
- Added: Build script with codesigning support (resources/scripts/build.sh)
- Added: Info.plist with UTI declarations for Markdown document types
- Added: Automated tests for document loading (UTF-8, empty, large files)
- Added: SwiftLint configuration

## 260110 Implementation Specs
- Added: 11 implementation specs breaking down PRD into stages
  - Stage 1: App Shell (file open, recent files, window management)
  - Stage 2: WebView Renderer (markdown-it, sourcepos, theming)
  - Stage 3: Git Repo Detection
  - Stage 4: Git Diff Parsing
  - Stage 5: Git Gutter (core feature)
  - Stage 6: File Watching (auto-refresh)
  - Stage 7: Git State Watching (index/HEAD changes)
  - Stage 8: Find in Page
  - Stage 9: Preferences
  - Stage 10: Print Support
  - Stage 11: Security & Sandbox
- Added: MCP UI Verification section to PROJECT.md
- Changed: Each spec includes automated tests + MCP-based UI verification

## 260107 Project Setup
- Added: PROJECT.md with project guidelines and folder structure
- Added: PRD spec for RedMargin macOS Markdown viewer with Git gutter
- Added: Initial folder structure (src/, WebRenderer/, Tests/, resources/)
