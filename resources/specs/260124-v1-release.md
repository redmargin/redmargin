# Version 1.0 Release

## Meta
- Status: Draft
- Branch: feature/v1-release

---

## Business

### Problem
Redmargin has exceeded its original MVP scope with remote file support and PDF export, but lacks features users expect from a polished 1.0 release: syntax highlighting in code blocks, folder navigation for browsing repo docs, and auto-updates.

### Solution
Add syntax highlighting via highlight.js, a minimal sidebar showing Markdown files in the current repo, and bump all version references to 1.0.0.

### Behaviors

**Syntax Highlighting**
- Code blocks with language specifiers (```python, ```javascript, etc.) render with syntax coloring
- Theme-aware: light theme uses light highlighting, dark theme uses dark highlighting
- Unsupported languages fall back to plain monospace text

**Sidebar**
- Toggle via View > Show Sidebar (Cmd-1) or hide via View > Hide Sidebar (Cmd-1)
- Shows Markdown files (.md, .markdown) in current file's Git repo root
- If file is not in a repo, shows Markdown files in the file's directory
- Single-click opens file in current window
- Current file highlighted in list
- Sidebar state (visible/hidden, width) persists per-window
- Remote files: sidebar shows remote directory listing via existing RPC

---

## Technical

### Approach

**Syntax Highlighting:** Integrate highlight.js into the WebRenderer bundle. markdown-it has a `highlight` option that receives code and language, returns highlighted HTML. Load highlight.js with a subset of common languages (python, javascript, typescript, swift, rust, go, java, bash, json, yaml, sql, html, css, markdown). Use highlight.js themes that complement existing light/dark themes.

**Sidebar:** Add `NSSplitViewController` wrapper around document content. Left pane contains `NSOutlineView` (or SwiftUI `List`) showing file tree. FileTreeProvider class enumerates Markdown files from repo root (via `GitRepoDetector.repoRoot`) or file's parent directory. Watch directory for changes using existing `FileWatcher` pattern. For remote files, use existing `SSHConnectionManager.listDirectory` RPC.

### File Changes

**WebRenderer/src/vendor/highlight.min.js** (create)
- highlight.js core + selected language modules bundled
- Include: python, javascript, typescript, swift, rust, go, java, bash, shell, json, yaml, xml, sql, html, css, markdown, diff, plaintext

**WebRenderer/src/highlight.js** (create)
- Wrapper that registers highlight.js with markdown-it
- Exports `configureHighlighting(md)` function

**WebRenderer/src/index.js** (modify)
- Import and call `configureHighlighting(md)` after markdown-it init
- Pass highlight function to markdown-it options

**WebRenderer/styles/highlight-light.css** (create)
- Light theme syntax colors (GitHub-style or similar)

**WebRenderer/styles/highlight-dark.css** (create)
- Dark theme syntax colors

**WebRenderer/styles/light.css** (modify)
- Import highlight-light.css

**WebRenderer/styles/dark.css** (modify)
- Import highlight-dark.css

**src/Views/SidebarView.swift** (create)
- SwiftUI view showing file list
- FileTreeProvider for enumerating .md files
- Selection binding to open files
- Directory watcher integration

**src/Views/SidebarSplitView.swift** (create)
- NSSplitViewController wrapper combining sidebar + document content
- Manages sidebar visibility state
- Handles divider position persistence

**AppMain/DocumentView.swift** (modify)
- Wrap DocumentWindowContent in SidebarSplitView
- Pass file selection handler to sidebar

**AppMain/RemoteDocumentView.swift** (modify)
- Wrap RemoteDocumentWindowContent in SidebarSplitView
- Use remote directory listing for sidebar content

**AppMain/MainMenu.swift** (modify)
- Add View > Show/Hide Sidebar (Cmd-1)

**build/Info.plist** (modify via build.sh)
- Update CFBundleShortVersionString to 1.0.0
- Update CFBundleVersion to 1.0.0

**README.md** (modify)
- Update Status line to v1.0.0
- Add Cmd-1 to keyboard shortcuts table

**src/Core/Remote/Client/ServerDeployer.swift** (modify)
- Update version constant to "1.0.0"

### Risks

| Risk | Mitigation |
|------|------------|
| highlight.js bundle size too large | Use official common build; measure bundle size before/after |
| Sidebar file enumeration slow for large repos | Limit depth, ignore node_modules/.git/etc, async enumeration with placeholder |
| Sidebar conflicts with existing window state | Persist sidebar state separately from document state; test with saved windows |

### Implementation Plan

**Phase 1: Syntax Highlighting**
- [x] Download highlight.js and create custom bundle with selected languages
- [x] Create highlight-light.css and highlight-dark.css themes
- [x] Create WebRenderer/src/highlight.js wrapper
- [x] Modify index.js to configure markdown-it with highlight function
- [x] Import highlight CSS in light.css and dark.css
- [ ] Test with code blocks in various languages
- [ ] Verify theme switching works correctly

**Phase 2: Sidebar - Local Files**
- [ ] Create FileTreeProvider class to enumerate .md files from directory
- [ ] Create SidebarView SwiftUI component
- [ ] Create SidebarSplitView wrapper using NSSplitViewController
- [ ] Integrate into DocumentView
- [ ] Add View menu items (Show/Hide Sidebar, Cmd-1)
- [ ] Add directory watching for sidebar refresh
- [ ] Persist sidebar visibility and width
- [ ] Test with repos of various sizes

**Phase 3: Sidebar - Remote Files**
- [ ] Extend FileTreeProvider to support remote directory listing
- [ ] Integrate into RemoteDocumentView
- [ ] Handle connection state (show placeholder when disconnected)
- [ ] Test remote sidebar navigation

**Phase 4: Version Bump and Polish**
- [ ] Update Info.plist version to 1.0.0
- [ ] Update ServerDeployer version to 1.0.0
- [ ] Update README status to v1.0.0
- [ ] Add Cmd-1 to README keyboard shortcuts
- [ ] Final testing of all new features
- [ ] Update CHANGELOG.md with 1.0 release notes

---

## Testing

### Automated Tests

Tests in `Tests/SidebarTests.swift`:
- [ ] `testFileTreeProviderFindsMarkdownFiles` - Directory with .md files returns correct list
- [ ] `testFileTreeProviderIgnoresNonMarkdown` - .txt, .swift files excluded
- [ ] `testFileTreeProviderUsesRepoRoot` - File in repo uses repo root, not file directory
- [ ] `testFileTreeProviderFallsBackToDirectory` - File not in repo uses parent directory

Tests in `WebRenderer/tests/highlight.test.js`:
- [ ] `testPythonHighlighting` - Python code block has syntax classes
- [ ] `testUnknownLanguageFallback` - Unknown language renders as plain code
- [ ] `testNoLanguageSpecifier` - Code block without language renders correctly

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### User Verification

After implementation, Marco verifies:

- [ ] Code blocks with ```python, ```javascript show colored syntax
- [ ] Syntax colors change appropriately between light/dark themes
- [ ] Cmd-1 toggles sidebar visibility
- [ ] Sidebar shows .md files from repo root
- [ ] Clicking file in sidebar opens it
- [ ] Sidebar works for remote files
- [ ] App version shows 1.0.0 in About dialog

---

## Maybe Later

### Auto-Updates (Sparkle)
- Add Sparkle.framework via SPM for automatic update checking
- Configure `SUFeedURL` in Info.plist pointing to GitHub-hosted appcast.xml
- Release script generates appcast entry with DMG URL, version, and EdDSA signature
- Menu item: Redmargin > Check for Updates...
- Check for updates on launch (after 5 second delay)
