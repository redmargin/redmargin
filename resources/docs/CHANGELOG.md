# Changelog

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
