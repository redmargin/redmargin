# PRD — RedMargin: macOS Markdown Viewer with Git Gutter in Rendered View

Owner: Engineering  
Status: Draft for implementation  
Target platforms: macOS 14+ (Apple Silicon first-class; Intel best-effort)  
Repo type: Local Git repositories (non-bare), including subdirectories (docs/), optional submodules


## Business

### Problem statement
Teams that maintain Markdown-heavy repositories (docs, runbooks, specs) want a reading-first experience (beautiful rendered Markdown with reliable search and copy), while also requiring Git-style change awareness (gutter change markers) to review edits at-a-glance without switching to source mode or a separate diff tool.

Existing tools typically provide either:
- High-quality rendered viewing without Git gutters, or
- Git gutters in source mode only, with a separate rendered preview that loses the gutter context.

RedMargin delivers a read-only (or reading-first) Markdown viewer where the rendered view includes a Git gutter that indicates modified/added/deleted lines similarly to VS Code/Zed.

### Goals
1. Render Markdown beautifully and clearly, with excellent support for:
   - Tables
   - Task lists / checkboxes
   - Code blocks, inline code, links, images
2. Display Git “gutter” change indicators aligned with the rendered content:
   - Modified lines (working tree changes vs HEAD)
   - Added lines
   - Deleted-line indicators (anchored appropriately)
3. Provide search within rendered mode (find-in-page) with highlights and navigation.
4. Allow copying text directly from the rendered view (native selection).
5. Keep the experience responsive and stable for typical docs workflows.

### Non-goals (explicit)
- Building a full Markdown editor (editing may be added later; MVP is viewer-first).
- Supporting non-Git version control systems.
- Perfect, word-level diff visualisation in rendered view (this is a gutter marker product, not a diff/merge tool).
- Remote repository browsing (e.g., GitHub web); local filesystem only in MVP.

### Primary users
- Engineers and technical writers reading docs and reviewing changes while authoring elsewhere (Zed/VS Code/JetBrains).
- Reviewers who want a fast “what changed?” scan without reading raw diffs.

### Success metrics (MVP)
- Time-to-open and render a typical 200–2,000 line Markdown file: < 300 ms after warm-up on Apple Silicon.
- Gutter alignment “feels correct” in manual review for standard documents; no obvious drift while scrolling/resizing.
- Search in rendered view works reliably (next/previous, highlights), with keyboard shortcuts.
- Copy from rendered view preserves readable text (not necessarily Markdown source).

### MVP scope
- Open a Markdown file from disk.
- Identify repository root and compute Git changes for that file.
- Render Markdown to HTML in a WKWebView, including `data-sourcepos` attributes.
- Overlay a left gutter in rendered view showing change markers for changed line ranges.
- Rendered find-in-page + copy selection.
- File and repo change watching (auto-refresh with debounce).

### Out of scope for MVP but planned (V1+)
- Side-by-side rendered vs source mode toggle.
- Staging/unstaging, commit, blame.
- Theme editor, custom CSS import UI.
- Multi-file navigation with sidebar (folder tree) beyond “Open Recent”.


## Technical

### High-level architecture
Native macOS app with SwiftUI/AppKit shell and a WKWebView-based renderer.

Components:
1. **App shell (SwiftUI/AppKit)**
   - Window management, file open, recent files, preferences
   - Repo detection and change computation
   - Watches for file and Git changes and triggers re-render

2. **Rendering engine (JS bundle inside WKWebView)**
   - Markdown parsing and HTML generation (GFM-friendly)
   - Emits source-position metadata: `data-sourcepos="startLine:startCol-endLine:endCol"` on block-level nodes
   - Draws gutter markers aligned to rendered blocks via DOM measurement

3. **Git change provider (Swift)**
   - For MVP, uses system `git` via `Process` (shell-out)
   - Computes changed line ranges in the *new file* coordinate space (working tree)
   - Produces a compact JSON payload for JS: changed ranges + optional deletion markers

Data flow:
- Swift loads Markdown text → computes Git change ranges → sends `{ markdown, changedRanges, deletedAnchors }` to JS.
- JS renders HTML with sourcepos → computes block rectangles → paints gutter overlay.
- On scroll/resize, JS repositions gutter markers without re-rendering Markdown.

### Technology choices
- UI: SwiftUI (preferred) with AppKit interop where needed
- Web rendering: WKWebView
- Find-in-page: WKWebView’s native find API (WKFindConfiguration)
- Markdown rendering: **markdown-it** in embedded JS (GFM plugins as needed)
- Git integration: `git diff --unified=0` parsing in Swift (MVP)
- File watching: FSEvents or DispatchSource + debounce

Rationale (implementation-oriented):
- Git gutters are line-based; rendered view is layout-based. `data-sourcepos` creates a stable mapping.
- WKWebView provides native selection, copy, and robust find-in-page.
- JS is the most practical layer to measure DOM geometry and paint a scrolling-synchronous gutter.

### Functional requirements (detailed)

#### FR-1 File open & repo detection
- User can open a `.md`/`.markdown` file (File → Open, drag/drop, or Finder “Open With”).
- App determines the Git repository root for the file:
  - Prefer: `git -C <dir> rev-parse --show-toplevel`
  - Handle: files in subdirectories, worktrees, submodules (best-effort: treat submodule as its own repo when applicable).
- If the file is not within a Git repo:
  - Render Markdown without gutter markers (empty gutter or hidden gutter based on preference).

#### FR-2 Markdown rendering quality
- Must support, at minimum:
  - GFM tables
  - Task lists / checkboxes
  - Fenced code blocks + syntax highlighting (optional MVP; acceptable to ship without highlighting in MVP if rendering remains correct)
  - Inline HTML handling (default: allow, but sanitise for safety; see Security)
  - Images (relative paths resolved from file directory; remote images optional, default off for privacy)
- Styling:
  - Provide at least 2 built-in themes (light/dark) aligned with system appearance.
  - Typography must remain readable at typical macOS font sizes; code blocks must wrap or scroll horizontally based on preference.

#### FR-3 Git gutter in rendered view
- Rendered view includes a left gutter visible alongside content.
- Gutter shows change markers similar to VS Code:
  - Added lines: bar (e.g., green)
  - Modified lines: bar (e.g., blue)
  - Deleted lines: marker at nearest anchor point (see below)
- Markers must scroll synchronously with the rendered content.
- Mapping logic:
  - The renderer emits `data-sourcepos` on block-level elements.
  - JS maps changed line ranges to block elements by overlap between:
    - element source line interval [startLine, endLine]
    - changed line interval [a, b]
  - If overlap exists: mark that element’s gutter segment.
- Deleted lines handling (MVP approach):
  - Deleted hunks have no “new lines”; represent as an anchor at the nearest following line number.
  - JS paints a small deletion marker at the top of the anchored block’s rectangle.
  - If deletion is at EOF: anchor to the last block.

#### FR-4 Search in rendered view
- Provide in-rendered search (Cmd+F) with:
  - Input field
  - Next/previous navigation
  - Match count / current index (if supported by WKWebView find API)
- Search should work without switching out of rendered mode.

#### FR-5 Copy from rendered view
- Native text selection in WKWebView must be enabled.
- Copy (Cmd+C) copies selected rendered text to clipboard.
- Links copied as text is acceptable in MVP; rich HTML copy is optional.

#### FR-6 Auto-refresh
- When the file changes on disk, re-render after debounce (e.g., 150–300 ms).
- When Git state changes affecting the file (working tree edits, staging, branch changes), recompute diff and update gutter after debounce.
- Avoid thrash:
  - Coalesce multiple events.
  - Cancel prior outstanding render jobs if a new one is queued.

### Non-functional requirements

#### Performance
- Must remain smooth while scrolling; gutter overlay updates must not drop frames during normal scroll.
- Avoid full Markdown re-render on every scroll; only reposition markers on scroll/resize.

#### Reliability
- No crashes on:
  - Very large files (target: 10k lines; degrade gracefully)
  - Unusual Unicode, long table rows, wide code blocks
  - Missing images / broken links

#### Security & privacy
- Default: block remote network loads in WKWebView (privacy-first).
- Sanitise inline HTML to prevent script execution:
  - Disable JS execution from Markdown content; only allow the app’s own bundled JS.
  - Strip or block `<script>`, event handlers, and potentially dangerous URLs.
- File URL access:
  - Allow loading relative local images within the file’s directory (or a controlled allowlist).
- Provide a preference toggle to allow remote images if desired.

#### Sandboxing & entitlements
- Support sandboxed distribution (App Store-compatible if desired):
  - Use security-scoped bookmarks for opened files and their directories if needed for relative assets.
  - Avoid unrestricted filesystem traversal beyond the selected file context.

### Key technical design details

#### Git change computation (Swift)
MVP algorithm:
1. Run:
   - `git -C <repoRoot> diff --unified=0 -- <relativePath>`
2. Parse unified diff hunks:
   - Hunk header format: `@@ -oldStart,oldCount +newStart,newCount @@`
3. Produce:
   - `changedRanges`: list of `[startLine, endLine]` for hunks where `newCount > 0`
     - Treat both additions and modifications as “changed” in MVP; optionally distinguish by checking whether `oldCount == 0` (pure add) vs `oldCount > 0` (modify).
   - `deletedAnchors`: list of `anchorLine` for hunks where `newCount == 0` and `oldCount > 0`
     - Use `anchorLine = newStart` (or `newStart-1` if more visually intuitive; define and test)

Edge cases:
- Renames: if file is renamed, `git diff` on the path may not show history; MVP accepts this.
- Untracked files: treat as “all added” (if file exists but not tracked); detect via `git ls-files --error-unmatch -- <path>`.

#### Rendering & gutter painting (JS)
- Use markdown-it configured for GFM tables and task lists.
- Ensure block elements include `data-sourcepos` attributes.
- After render:
  - Query all elements with `data-sourcepos`.
  - Parse sourcepos into `[startLine, endLine]`.
  - Determine if element overlaps any changed range.
  - For each overlapped element, compute rect relative to scroll container.
  - Draw gutter segments as absolutely positioned divs in a fixed gutter layer.
- Update strategy:
  - On scroll: recompute vertical positions using cached element refs; avoid re-parsing Markdown.
  - On resize/font/theme change: reflow and recompute rects.

#### Bridging Swift ↔ JS
- Use `WKUserScript` to inject the renderer bundle at document start.
- Use `evaluateJavaScript` to call a JS entrypoint:
  - `window.App.render({ markdown, changedRanges, deletedAnchors, options })`
- Options includes:
  - theme (light/dark/system)
  - allowRemoteImages (bool)
  - basePath for relative asset resolution

#### Watching changes
- File changes:
  - Watch the open file path; re-read and re-render on write/rename.
- Git changes:
  - Watch `<repoRoot>/.git/index` and HEAD reference changes for branch switches.
  - In worktrees, `.git` may be a file pointing elsewhere; resolve actual gitdir via `git rev-parse --git-dir` and watch that directory.

### Deliverables
- RedMargin macOS app (signed) with:
  - Open file dialog + recent files
  - Rendered view with gutter markers
  - Find-in-page
  - Copy selection
  - Preferences (minimum: theme/system, show/hide gutter when no repo, allow remote images)


## Testing

### Acceptance criteria (must-pass for MVP)
1. Open a Markdown file in a Git repo → rendered view shows gutter markers for edited lines (working tree vs HEAD).
2. Gutter markers stay aligned while scrolling, resizing the window, and toggling dark mode.
3. Cmd+F searches within the rendered view and navigates matches.
4. Text can be selected and copied from rendered view.
5. Tables render correctly; task list checkboxes render correctly.
6. App auto-refreshes when the file changes and when Git changes occur (e.g., stage/unstage, checkout another branch).

### Test strategy overview
- Unit tests (Swift): git diff parsing, repo root detection, path handling, change-range computation.
- Unit tests (JS): sourcepos parsing, overlap logic, deletion anchoring logic.
- Integration tests: sample repos with known diffs, end-to-end render + gutter screenshot diffs.
- UI tests: open file, verify find, copy, theme switching.
- Performance tests: large Markdown files and rapid change events.

### Unit tests (Swift)
1. **Repo detection**
   - File inside repo root
   - File inside nested folder
   - File inside submodule
   - File outside any repo
2. **Diff parsing**
   - Pure additions: `oldCount=0,newCount>0`
   - Pure deletions: `newCount=0,oldCount>0`
   - Modifications: `oldCount>0,newCount>0`
   - Multiple hunks
   - No hunks (clean file)
3. **Untracked file behaviour**
   - Ensure app marks all lines as “added” or shows “untracked” state deterministically.

### Unit tests (JS)
1. `data-sourcepos` parsing correctness
2. Overlap detection between element line intervals and changed ranges
3. Deletion anchor placement near:
   - middle of file
   - beginning of file
   - end of file / EOF

### Integration tests
Prepare a `fixtures/` folder with small Git repos:
- `tables-and-tasks/` (tables + checkboxes; changed rows/lines)
- `images-relative/` (relative image paths)
- `deletions-only/` (deleted lines hunks)
- `large-file/` (generated 10k lines)

For each fixture:
- Run app in test harness to load file.
- Verify gutter segments exist in expected vertical ranges (DOM query + numeric tolerance).
- Optional: snapshot testing of rendered HTML and gutter overlay positions.

### UI tests (XCUITest)
- Open recent file and verify content visible.
- Cmd+F: search term → next/previous navigation changes selection.
- Copy: select paragraph → Cmd+C → clipboard contains expected substring.
- Toggle theme: system light/dark → rendered theme updates and gutter remains aligned.

### Performance tests
- Load 10k-line Markdown file:
  - Cold load time
  - Re-render time on edit
  - Scroll smoothness baseline (manual + automated metrics if feasible)
- Burst changes:
  - Simulate multiple file writes and git index updates; ensure debounce prevents CPU spikes.

### Manual QA checklist (release gate)
- No remote requests when remote images disabled (verify with a network monitor).
- Sandboxed behaviour: reopen a file after app relaunch (bookmark correctness).
- Unicode and RTL snippets do not break layout.
- Very wide tables/code blocks behave per preference (wrap vs horizontal scroll).


---
Appendix (implementation notes)
- Prefer a minimal first release: correct mapping + alignment beats fancy features.
- Distinguish added vs modified in gutter in V1 if desired; MVP can show “changed” uniformly with one color and still meet the core requirement.
