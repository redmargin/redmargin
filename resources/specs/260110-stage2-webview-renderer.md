# WebView Renderer

## Meta
- Status: In Progress
- Branch: feature/webview-renderer
- Dependencies: 260110-stage1-app-shell.md

---

## Business

### Problem
RedMargin needs to render Markdown as beautifully formatted HTML. The rendered output must include `data-sourcepos` attributes on block elements so that later specs can map source lines to rendered positions for the Git gutter.

### Solution
Embed a WKWebView in the document window. Use markdown-it (JavaScript) to parse Markdown and emit HTML with sourcepos attributes. Support light/dark themes that follow system appearance.

### Behaviors
- **Rendered view:** Markdown displays as formatted HTML (headings, lists, tables, code blocks, etc.)
- **Theme switching:** Automatically follows macOS light/dark mode
- **Tables:** GFM tables render correctly
- **Task lists:** Checkboxes are interactive - clicking toggles `[ ]` ↔ `[x]` in source, saves file immediately, updates DOM in place (no full re-render)
- **Code blocks:** Fenced code blocks render with monospace font (syntax highlighting optional for MVP)
- **Images:** Local relative images display; remote images blocked by default
- **Line numbers:** Optional gutter showing source line numbers, aligned with rendered content using `data-sourcepos` attributes
- **App icon:** Uses RedMargin icon pack for app icon

---

## Technical

### Approach
Replace the placeholder `Text` view from app-shell with an `NSViewRepresentable` wrapping `WKWebView`. The WebView loads a local HTML page that includes the markdown-it library. Swift sends Markdown content to JS via `evaluateJavaScript`, calling `window.App.render({ markdown, options })`. The JS renders to HTML and inserts into the DOM.

For sourcepos: Use markdown-it with a plugin or custom renderer rule that adds `data-sourcepos="startLine:startCol-endLine:endCol"` to block-level elements (paragraphs, headings, lists, tables, code blocks).

Theme: Inject CSS variables or swap stylesheets based on system appearance. Observe `NSApp.effectiveAppearance` changes.

### File Changes

**src/Views/MarkdownWebView.swift** (create)
- `NSViewRepresentable` wrapping `WKWebView`
- Configure WKWebView: disable JS from content (only allow bundled JS), set `allowsLinkPreview = false`
- Load the renderer HTML from bundle
- Expose `render(markdown: String, options: RenderOptions)` method
- Handle appearance changes to update theme

**src/Views/DocumentView.swift** (modify)
- Replace `Text` placeholder with `MarkdownWebView`
- Pass document content to the WebView for rendering
- Observe document changes and re-render

**WebRenderer/src/index.js** (create)
- Import and configure markdown-it with GFM tables, task lists
- Add sourcepos plugin/rule to emit `data-sourcepos` on block elements
- Export `window.App.render({ markdown, changedRanges, deletedAnchors, options })`
- `options.theme`: 'light' | 'dark'
- `options.basePath`: for resolving relative image paths

**WebRenderer/src/sourcepos.js** (create)
- markdown-it plugin that adds `data-sourcepos` attributes
- Use token.map (which markdown-it provides) to get [startLine, endLine]
- Format as `data-sourcepos="startLine:0-endLine:0"` (column is 0 for block elements)

**WebRenderer/src/renderer.html** (create)
- Base HTML document loaded by WKWebView
- Include bundled JS (index.js)
- Include theme CSS
- Container div for rendered content
- Gutter container div (empty for now, used by git-gutter spec)

**WebRenderer/styles/light.css** (create)
- Light theme styles: typography, headings, code blocks, tables, task lists
- CSS variables for colors that can be overridden

**WebRenderer/styles/dark.css** (create)
- Dark theme styles matching macOS dark mode aesthetics
- Same structure as light.css with different color values

**WebRenderer/src/checkboxHandler.js** (create)
- Click handler for task list checkboxes
- Extracts source line from `data-sourcepos` on parent `<li>` element
- Calls `webkit.messageHandlers.checkboxToggle.postMessage({ line, checked })`
- Updates checkbox DOM state immediately (no re-render needed)

**WebRenderer/src/lineNumbers.js** (create)
- Generates line number elements in gutter based on `data-sourcepos` attributes
- Aligns line numbers with rendered block elements by matching DOM positions
- Called after render to populate `#gutter-container`

**src/Views/MarkdownWebView.swift** (modify)
- Add `WKScriptMessageHandler` for `checkboxToggle` messages
- Add callback closure `onCheckboxToggle: ((Int, Bool) -> Void)?` to notify parent
- Register message handler in WKWebView configuration

**src/App/RedMarginApp.swift** (modify)
- Change `DocumentWindowContent` to use `@State var content` instead of `let content`
- Pass `onCheckboxToggle` callback to MarkdownWebView
- Callback toggles checkbox in markdown source string and saves file immediately
- Store `fileURL` for saving

**resources/scripts/build.sh** (modify)
- Add step to bundle WebRenderer assets into app bundle Resources/

**Icon Integration**
- Extract `RedMargin_IconPack.zip` to `resources/`
- Convert `RedMargin.iconset` to `RedMargin.icns` using `iconutil`
- Add icon to app bundle via build script or Xcode asset catalog

### Risks

| Risk | Mitigation |
|------|------------|
| markdown-it sourcepos not accurate | Test with various Markdown structures; the built-in token.map should work for blocks |
| WKWebView sandbox blocks local images | Use `loadFileURL(_:allowingReadAccessTo:)` with the file's directory |
| Theme not updating on system change | Use `NSApp.effectiveAppearance` observation and re-inject CSS or call JS |
| Large files slow to render | Profile with 10k line files; consider chunking if needed |

### Implementation Plan

**Phase 1: Basic WebView**
- [x] Create `WebRenderer/src/renderer.html` with minimal HTML structure
- [x] Create `src/Views/MarkdownWebView.swift` as NSViewRepresentable
- [x] Load renderer.html from bundle in WKWebView
- [x] Verify WebView displays in document window (shows blank page or "Hello")

**Phase 2: markdown-it Integration**
- [x] Download markdown-it library, place in `WebRenderer/src/vendor/`
- [x] Create `WebRenderer/src/index.js` with basic markdown-it setup
- [x] Configure GFM tables plugin (`markdown-it-gfm-tables` or built-in)
- [x] Configure task list plugin
- [x] Test rendering simple Markdown in browser (standalone test)

**Phase 3: Sourcepos Plugin**
- [x] Create `WebRenderer/src/sourcepos.js` plugin
- [x] Hook into markdown-it renderer to add `data-sourcepos` to block elements
- [x] Test: render Markdown, inspect DOM, verify sourcepos attributes present and accurate
- [x] Create fixture file with known line numbers, verify mapping

**Phase 4: Swift-JS Bridge**
- [x] Implement `render(markdown:options:)` in MarkdownWebView
- [x] Call `evaluateJavaScript("window.App.render(...)")` with JSON payload
- [x] Update DocumentView to call render when document loads
- [x] Verify Markdown renders in the app window

**Phase 5: Theming**
- [x] Create `WebRenderer/styles/light.css` with full styling
- [x] Create `WebRenderer/styles/dark.css` with dark mode styling
- [x] Add appearance observation in MarkdownWebView
- [x] Call JS to switch theme on system appearance change
- [ ] Test light/dark mode switching in System Preferences

**Phase 6: Build Integration**
- [x] Update `resources/scripts/build.sh` to copy WebRenderer to bundle
- [x] Verify built app loads and renders correctly

**Phase 7: Interactive Checkboxes**
- [x] Create `WebRenderer/src/checkboxHandler.js` with click handler
- [x] Add `WKScriptMessageHandler` to MarkdownWebView.swift for `checkboxToggle`
- [x] Update RedMarginApp.swift to use `@State` for content and handle checkbox toggles
- [x] Implement markdown source modification (toggle `[ ]` ↔ `[x]` on target line)
- [x] Save file immediately after toggle
- [x] Test checkbox toggle updates DOM and saves file

**Phase 8: Line Numbers**
- [x] Create `WebRenderer/src/lineNumbers.js` to generate gutter line numbers
- [x] Add CSS for line number styling in both themes
- [x] Call line number generation after render
- [x] Add View menu toggle for line numbers (Cmd+L)
- [x] Test line numbers align with rendered content

**Phase 9: App Icon**
- [x] Extract icon pack to `resources/`
- [x] Convert iconset to .icns
- [x] Update build script to include icon in app bundle
- [x] Verify icon appears in Finder and Dock

**Phase 10: Scroll Position Persistence**
- [x] Create `WebRenderer/src/scrollPosition.js` for scroll tracking
- [x] Add `WKScriptMessageHandler` for `scrollPosition` messages
- [x] Save scroll positions to UserDefaults keyed by file path
- [x] Restore scroll position on document reopen
- [x] Preserve window z-order on app relaunch

---

## Testing

### Automated Tests

**Swift tests** in `Tests/MarkdownWebViewTests.swift`:

- [ ] `testWebViewLoadsRendererHTML` - Create MarkdownWebView, verify it loads without error (check for JS errors via WKNavigationDelegate)
- [ ] `testRenderCallReturnsWithoutError` - Call render() with simple Markdown, verify no JS exceptions thrown

**JavaScript tests** in `WebRenderer/tests/` (run with Node or browser test runner):

- [x] `testMarkdownItRendersBasicMarkdown` - Input: `# Hello`, Output contains `<h1>`
- [x] `testSourceposOnHeading` - Input: `# Hello`, Output `<h1>` has `data-sourcepos="1:0-1:0"`
- [x] `testSourceposOnParagraph` - Input: `Line 1\n\nLine 3`, verify paragraph sourcepos is `3:0-3:0`
- [x] `testSourceposOnMultilineBlock` - Input: multiline code block on lines 2-5, verify sourcepos is `2:0-5:0`
- [x] `testSourceposOnTable` - Input: GFM table, verify table element has correct sourcepos
- [x] `testSourceposOnListItems` - Input: bullet list, verify each `<li>` has sourcepos
- [x] `testGFMTableRenders` - Input: GFM table, Output contains `<table>` with correct cells
- [x] `testTaskListRenders` - Input: `- [ ] unchecked\n- [x] checked`, Output has checkbox inputs

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| 2026-01-10 | PASS | All 10 JS tests pass (sourcepos, tables, task lists) |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify rendering. Open a test .md file in RedMargin first.

**Note:** WKWebView content is not directly accessible via accessibility APIs. These checks verify the app structure; rendering correctness relies on JS unit tests and visual spot-checks.

- [x] **WebView present:** `find_elements_in_app("RedMargin", "$..[?(@.role=='webArea' || @.role=='group')]")` finds the WebView container
- [x] **Window has content:** `find_elements_in_app("RedMargin", "$..[?(@.role=='window')]")` returns window with non-empty structure
- [ ] **Theme follows system:** Toggle system appearance via System Preferences, re-query app - no crash, window still present

### Manual Verification (WebView internals)

- [x] **Rendering quality:** Visual check that headings, tables, code blocks, task lists render correctly
- [ ] **Sourcepos attributes:** Use Safari Web Inspector (Develop menu) to inspect WebView DOM, verify `data-sourcepos` on block elements
- [ ] **Local images:** Reference `![](test-image.jpg)` in a .md file, verify it displays

![Test image for local image rendering](test-image.jpg)
