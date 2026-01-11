# Changelog

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
- Added: 10 implementation specs breaking down PRD into stages
  - Stage 1: App Shell (file open, recent files, window management)
  - Stage 2: WebView Renderer (markdown-it, sourcepos, theming)
  - Stage 3: Git Repo Detection
  - Stage 4: Git Diff Parsing
  - Stage 5: Git Gutter (core feature)
  - Stage 6: File Watching (auto-refresh)
  - Stage 7: Git State Watching (index/HEAD changes)
  - Stage 8: Find in Page
  - Stage 9: Preferences
  - Stage 10: Security & Sandbox
- Added: MCP UI Verification section to PROJECT.md
- Changed: Each spec includes automated tests + MCP-based UI verification

## 260107 Project Setup
- Added: PROJECT.md with project guidelines and folder structure
- Added: PRD spec for RedMargin macOS Markdown viewer with Git gutter
- Added: Initial folder structure (src/, WebRenderer/, Tests/, resources/)
