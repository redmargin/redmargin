# Changelog

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
