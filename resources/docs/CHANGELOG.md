# Changelog

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
