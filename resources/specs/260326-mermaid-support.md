# Mermaid Diagram Support

## Meta

- Status: Implemented
- Branch: feature/mermaid-support

---

## Business

### Goal

Add first-party Mermaid diagram rendering for fenced `mermaid` blocks without regressing Redmargin's existing source mapping, security, theme switching, or print/PDF behavior.

### Proposal

Render fenced Mermaid blocks as diagrams in the Markdown preview for local and remote documents. Keep the feature safe and predictable by treating Mermaid as a renderer enhancement, not as a second path for arbitrary HTML or script execution.

### Behaviors

User-facing behaviors:

- Fenced code blocks whose info string is exactly `mermaid` render as diagrams instead of plain code blocks.
- Invalid Mermaid syntax shows an error banner with Mermaid's error message above the original source displayed as a regular code block, instead of rendering a blank block or breaking the rest of the document.
- Diagrams follow the current Redmargin light/dark theme and refresh when the theme changes.
- Git gutter indicators and line numbers remain anchored to the correct source line range for the Mermaid fence.
- Print preview and PDF export include Mermaid diagrams and use the active print/export theme rather than stale on-screen colors.
- Each rendered Mermaid block shows a copy button (matching the existing code block copy button style) that copies the original Mermaid source text, not the generated SVG.

### Out of scope

- Mermaid editing, zoom/pan controls, or diagram authoring tools
- User-controlled Mermaid `%%{init:}%%` directives, front matter config, custom theme CSS, or HTML labels
- Interactive Mermaid callbacks or link behavior beyond Redmargin's existing document navigation rules
- Remote assets or external diagram extensions/layout engines such as ELK
- Handling Mermaid diagrams taller than a full printed page (they will break across pages; fixing this requires SVG-to-image rasterization which is a separate feature)
- Cancellation UX for slow-rendering Mermaid blocks (render timeouts, per-block loading indicators, diagram count limits)

---

## Technical

### Approach

Bundle Mermaid >= 11.10.0 (the minimum version that includes fixes for CVE-2025-54881 and CVE-2025-54880) as `WebRenderer/src/vendor/mermaid.min.js` and keep Mermaid rendering fully app-controlled. Use the full `mermaid.min.js` bundle (~1.1 MB), not `@mermaid-js/tiny`, so all diagram types are supported. Add a new `WebRenderer/src/mermaid.js` wrapper that initializes Mermaid with safe defaults: `startOnLoad: false`, `securityLevel: 'strict'`, `htmlLabels: false`, `suppressErrorRendering: true`, and `theme` set to `'default'` for light or `'dark'` for dark mode. Do not use Mermaid's document-wide auto-run path because Redmargin already owns DOM insertion, scroll preservation, gutter generation, print preparation, and rerender timing.

Mermaid theme mapping:

| Redmargin context | Mermaid `theme` value |
| --- | --- |
| Light mode | `default` |
| Dark mode | `dark` |
| Print (light) | `default` |
| Print (dark) | `dark` |

Theme changes require a full Mermaid re-render because Mermaid bakes colors into SVG at render time. On theme change: call `mermaid.initialize()` with the new theme value, then call `mermaid.render(uniqueId, storedSource)` for each `.mermaid-block`, and replace the inner SVG. Await all re-renders before calling `LineNumbers.generate()` and `Gutter.update()`.

Modify `WebRenderer/src/index.js` so exact `mermaid` fences emit a `.mermaid-block` wrapper that preserves the fence's `data-sourcepos` and stores the original Mermaid text in a `data-source` attribute. After Markdown HTML is sanitized and inserted into `#content-container`, call `window.MermaidRenderer.renderBlocks()` (which returns a Promise), then regenerate line numbers and gutter markers in the `.then()` callback. In `setTheme()`, after swapping stylesheets, call `window.MermaidRenderer.rerenderForTheme(newTheme)` and chain `LineNumbers.generate()` and `Gutter.update()` on the returned Promise via `.then()`. Use `requestAnimationFrame` with a short timeout fallback when scheduling this post-DOM work so offscreen WKWebViews (tests, print prep) still run Mermaid rendering even when WebKit throttles animation frames.

Print preparation and PDF export call `window.MermaidRenderer.prepareMermaidForPrint(theme)` and `window.MermaidRenderer.restoreMermaidFromPrint(screenTheme)` directly from Swift via `callAsyncJavaScript`. These functions live on `window.MermaidRenderer` (exposed by `WebRenderer/src/mermaid.js`), not on `window.App`. Swift callers: `src/Views/MarkdownWebView.swift`, `AppMain/DocumentView.swift`, `AppMain/FolderWindowContent.swift`, `AppMain/RemoteDocumentView.swift`, and `src/Printing/PDFExporter.swift`. Because Redmargin swaps a single theme stylesheet at runtime, the light print palette cannot rely on `light.css` being mounted; `WebRenderer/styles/print.css` must define the `print-light-theme` CSS variables needed for Mermaid block chrome and other print-only light styling when the screen is currently dark.

### Approach Validation

Official Mermaid docs confirm that site-wide `initialize()` configuration is the intended integration point, and that theme/security options such as `theme`, `securityLevel`, `startOnLoad`, `htmlLabels`, `secure`, and `suppressErrorRendering` are all application-level concerns rather than something Redmargin should leave to document content. The theming docs also confirm that Mermaid ships light, dark, and neutral/base theme paths, which maps cleanly to Redmargin's existing screen and print themes. Relevant references: [Theme Configuration](https://mermaid.js.org/config/theming.html), [MermaidConfig](https://mermaid.js.org/config/setup/mermaid/interfaces/MermaidConfig.html), [Diagram Syntax](https://mermaid.js.org/intro/syntax-reference.html).

Upstream Mermaid issues also reinforce the need for app-controlled sequential rendering. Issue [#4064](https://github.com/mermaid-js/mermaid/issues/4064) and PR [#4142](https://github.com/mermaid-js/mermaid/pull/4142) document async render hazards and queueing problems when `startOnLoad` and manual rendering overlap. Issue [#1601](https://github.com/mermaid-js/mermaid/issues/1601) and PR [#6621](https://github.com/mermaid-js/mermaid/pull/6621) show that fast multi-block rendering can still produce unstable or duplicate SVG IDs. Redmargin should therefore avoid Mermaid auto-scan behavior, render each block sequentially with explicit IDs, and treat Mermaid output as a post-sanitize SVG generation step with its own safety rules.

Two Mermaid XSS CVEs were disclosed in August 2025: CVE-2025-54881 (sequence diagram labels passed unsanitized to `innerHTML` via KaTeX delimiters) and CVE-2025-54880 (architecture diagram `iconText` passed unsanitized to d3 `html()`). Both were fixed in Mermaid 11.10.0. These CVEs bypassed Mermaid's built-in DOMPurify integration, reinforcing the need for Redmargin's own SVG sanitization pass after Mermaid rendering.

WebKit compatibility is a known concern: Mermaid 11.6.0 broke Safari < 16.5 due to unsupported JS syntax ([mermaid-js/mermaid#6666](https://github.com/mermaid-js/mermaid/issues/6666)). The bundled Mermaid version must be verified against the WebKit version shipped with macOS 14.0 (Safari 17.0) before release. WKWebView may also emit harmless `.map` file loading warnings that can be ignored.

User feedback across Markdown apps (Reddit, GitHub issues, forum threads) confirms that theme switching is the #1 pain point: apps that fail to re-render Mermaid SVGs on theme change leave stale colors. The spec addresses this by requiring full re-render on theme change with `mermaid.initialize()` + `mermaid.render()` per block. Copy-source access is the #2 request — users want the original Mermaid source after rendering, which this spec preserves via `data-source` attributes on `.mermaid-block` wrappers and a copy button per block.

### Risks

| Risk | Mitigation |
| ---- | ---------- |
| Mermaid SVG bypasses the current markdown HTML sanitizer and introduces a new XSS or tracking surface | Lock Mermaid to safe defaults, reject user-controlled Mermaid config in v1, add a dedicated SVG sanitization pass, and keep interactive/remote-asset features out of scope |
| Theme or print rerenders leave stale line numbers or git gutter positions | Chain `LineNumbers.generate()` and `Gutter.update()` on the Promise returned by `MermaidRenderer.renderBlocks()` and `MermaidRenderer.rerenderForTheme()`; print/export callers await `prepareMermaidForPrint()` before capturing |
| Multi-line Mermaid fences lose per-line number alignment because current logic only treats `pre` as a multi-line block | Extend `WebRenderer/src/lineNumbers.js` to treat `.mermaid-block` as a code-like block and add dedicated regression tests |
| Multiple Mermaid blocks collide on generated SVG IDs or race during rapid rerenders | Render blocks sequentially with explicit unique IDs and avoid Mermaid auto-run or parallel `run()` calls |
| Large or invalid diagrams degrade preview responsiveness | Catch render failures per block and fall back to source display; broader performance caps (render timeouts, diagram count limits) are out of scope for this spec |
| Bundled Mermaid version uses JS syntax unsupported by macOS 14.0's WebKit (Safari 17.0) | Verify the bundled Mermaid version loads and renders in a WKWebView on macOS 14.0 before release; add a WebRenderer test that imports mermaid.min.js without syntax errors |
| Mermaid JS fails to load entirely (syntax error, corrupted file) | `WebRenderer/src/mermaid.js` must check for `typeof mermaid !== 'undefined'` before calling any Mermaid API; if Mermaid is unavailable, all Mermaid fences fall back to rendering as plain code blocks with no error banner |

### Implementation Plan

**Phase 1: Renderer integration**

- [x] Download `mermaid.min.js` (>= 11.10.0) from `https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js` and save it as `WebRenderer/src/vendor/mermaid.min.js`. Verify the downloaded version is >= 11.10.0 by checking the header comment. Create `WebRenderer/src/mermaid.js` as an IIFE exposing `window.MermaidRenderer` with:
  - `initialize(theme)` — calls `mermaid.initialize()` with `startOnLoad: false`, `securityLevel: 'strict'`, `htmlLabels: false`, `suppressErrorRendering: true`, and the given `theme` value
  - `renderBlocks()` — returns a Promise. Queries all `.mermaid-block` elements; if none exist, resolves immediately. Otherwise renders each sequentially (awaiting each before starting the next) via `mermaid.render(uniqueId, source)` where `source` comes from the element's `data-source` attribute, sanitizes each SVG result through `window.Sanitizer.sanitizeMermaidSvg()`, and inserts it into the block. On per-block render failure (including empty source), sets that block to error state: an error banner (`<div class="mermaid-error">`) with Mermaid's error message, plus the original source in a `<pre><code>` block. The Promise resolves after all blocks are processed (including any that errored). Note: `sanitizeMermaidSvg` is implemented in Phase 2; during Phase 1 development, use a passthrough stub (`function(svg) { return svg; }`) and replace it in Phase 2
  - `rerenderForTheme(theme)` — calls `initialize(theme)` then `renderBlocks()` to re-render all existing Mermaid blocks with new theme colors. If a re-render is already in progress (from a prior theme change), discard the in-flight result and start the new re-render — track this via a generation counter that increments on each call, and check the counter after each block render to bail out if stale
  - `prepareMermaidForPrint(theme)` — calls `rerenderForTheme(theme)` and returns a Promise that resolves when all blocks are done
  - `restoreMermaidFromPrint(screenTheme)` — calls `rerenderForTheme(screenTheme)` and returns a Promise
  - Each `.mermaid-block` gets a copy button (reusing the existing `copy-btn` class and SVG icons from `index.js`) that reads from the element's `data-source` attribute
- [x] Update `WebRenderer/src/renderer.html` to load `vendor/mermaid.min.js` and `mermaid.js` in the script order — both after `sanitizer.js` and before `index.js`. Update `resources/scripts/build.sh` to add `cp WebRenderer/src/mermaid.js "$RESOURCES_DIR/WebRenderer/src/"` alongside the other explicit src copies (vendor files are already covered by the `cp WebRenderer/src/vendor/*.js` wildcard). Update `WebRenderer/package.json` test script to run all test files: `node tests/sourcepos.test.js && node tests/sanitizer.test.js && node tests/gutter.test.js && node tests/integration.test.js && node tests/mermaid.test.js`
- [x] Modify `WebRenderer/src/index.js`: override `md.renderer.rules.fence` to check if the info string is exactly `mermaid`. If so, emit `<div class="mermaid-block" data-sourcepos="..." data-source="..."></div>` (where `data-source` holds the HTML-escaped original Mermaid text and `data-sourcepos` is forwarded from the token) instead of the default `<pre><code>` output. For non-mermaid fences, delegate to the original fence renderer. After DOM insertion in `render()`, call `window.MermaidRenderer.renderBlocks()` and chain `LineNumbers.generate()` and `Gutter.update()` on the returned Promise via `.then()`. In `setTheme()`, after swapping stylesheets, call `window.MermaidRenderer.rerenderForTheme(newTheme)` and chain `LineNumbers.generate()` and `Gutter.update()` on the returned Promise

**Phase 2: Security and layout integration**

- [x] Add `window.Sanitizer.sanitizeMermaidSvg(svgString)` to `WebRenderer/src/sanitizer.js`. This function parses the SVG string via DOMParser, removes `<script>`, `<foreignObject>`, and `<iframe>` elements, strips all `on*` event handler attributes, removes `javascript:` and `data:` URLs from `href`/`xlink:href` attributes, and returns the sanitized SVG string. Keep this separate from the existing `sanitize()` HTML path — SVG has a different element/attribute allowlist (allow `<svg>`, `<g>`, `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<text>`, `<tspan>`, `<defs>`, `<marker>`, `<use>`, `<clipPath>`, `<mask>`, `<pattern>`, `<linearGradient>`, `<radialGradient>`, `<stop>`, `<title>`, `<desc>`)
- [x] Preserve `data-sourcepos` on `.mermaid-block` wrappers (already emitted by Phase 1 changes to `index.js`) and update `WebRenderer/src/lineNumbers.js` to treat `.mermaid-block` elements the same way it currently treats `pre` elements for multi-line blocks: distribute line number positions evenly across the element's rendered height for the full source range
- [x] Add styles for `.mermaid-block` (border, padding, background matching code blocks, `overflow-x: auto` for wide diagrams that exceed the content width), `.mermaid-error` (red/orange error banner text, `font-size: 0.85em`), and `.mermaid-block .copy-btn` (positioned like the existing `pre .copy-btn`) in `WebRenderer/styles/light.css` and `WebRenderer/styles/dark.css`. Add print-specific Mermaid styles in `WebRenderer/styles/print.css`: ensure `.mermaid-block` gets `page-break-inside: avoid` (diagrams taller than a full page will still break — this is acceptable and out of scope to fix), hide copy buttons in print, hide error banners in print, and define the `print-light-theme` CSS variables there so printing from a dark screen theme still uses the light block/background palette

**Phase 3: Print, PDF, and app hooks**

- [x] Update `MarkdownWebView.preparePrint(webView:config:completion:)` in `src/Views/MarkdownWebView.swift` to call `window.MermaidRenderer.prepareMermaidForPrint('default')` via `callAsyncJavaScript` after adding CSS classes (the print dialog path always uses light theme). Await the Promise resolution before calling `completion`. Update `MarkdownWebView.restoreFromPrint(webView:)` to accept an optional `screenTheme: String? = nil` parameter. When non-nil, call `window.MermaidRenderer.restoreMermaidFromPrint(screenTheme)` after removing CSS classes. When nil, skip Mermaid restore (backwards-compatible with existing callers and tests). Note: the current print callers (`DocumentView`, `FolderWindowContent`, `RemoteDocumentView`) add CSS classes directly via `evaluateJavaScript` instead of calling `MarkdownWebView.preparePrint()`, so each caller must also be updated (next task)
- [x] Update `executePrint()` in `AppMain/DocumentView.swift`, `AppMain/FolderWindowContent.swift`, and `AppMain/RemoteDocumentView.swift` to call `window.MermaidRenderer.prepareMermaidForPrint('default')` via `callAsyncJavaScript` after adding CSS classes and before running `printOperation` (the print dialog always uses light theme). Update each view's `PrintCompletionHandler` to call `window.MermaidRenderer.restoreMermaidFromPrint(screenTheme)` during cleanup, where `screenTheme` is the view's current `effectiveTheme`. Update `src/Printing/PDFExporter.swift` to call `prepareMermaidForPrint` with `'default'` for light theme or `'dark'` for dark theme (matching its existing `theme` parameter) after adding CSS classes and await it before running the export print operation, then call `restoreMermaidFromPrint` in `PDFExportCompletionHandler` with the same `theme` it was given. If Mermaid re-render fails during print preparation, log the error via `Logger` and proceed with the print (blocks will show their current state rather than blocking the entire print)
- [x] Update `README.md` and `resources/docs/CHANGELOG.md` for the new Mermaid feature once implementation is complete

**Phase 4: Regression coverage**

- [x] Add renderer coverage in `WebRenderer/tests/mermaid.test.js` for successful render, block-level fallback, theme rerender, copy-source behavior, and graceful degradation when Mermaid is unavailable
- [x] Add Mermaid SVG security coverage in `WebRenderer/tests/sanitizer.test.js`
- [x] Add Mermaid source mapping coverage in `WebRenderer/tests/sourcepos.test.js` and `WebRenderer/tests/integration.test.js`
- [x] Add WKWebView coverage in `Tests/MarkdownWebViewTests.swift` and `Tests/PrintTests.swift` for rendered diagrams, theme switching, and print preparation/restore

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one. Omit test types that don't apply.

### Unit Tests (`WebRenderer/tests/mermaid.test.js`)

- [x] `testMermaidFenceRendersSvg` - A valid ```` ```mermaid ```` fence produces a `.mermaid-block` wrapper containing a sanitized `<svg>` element
- [x] `testMermaidFenceFallsBackToSourceOnRenderError` - Invalid Mermaid syntax produces a `.mermaid-block` with a `.mermaid-error` banner and the original source in a `<pre><code>` block
- [x] `testMermaidThemeRerenderUpdatesExistingBlocks` - Calling `MermaidRenderer.rerenderForTheme('dark')` on a previously light-rendered block produces SVG with different fill/stroke colors
- [x] `testMermaidCopySourceUsesOriginalFenceText` - The `.mermaid-block` element's `data-source` attribute contains the original Mermaid text, and the copy button reads from it
- [x] `testMermaidGracefulDegradationWhenMermaidUnavailable` - When `mermaid` global is undefined, `MermaidRenderer.renderBlocks()` renders fences as plain code blocks without throwing

### Unit Tests (`WebRenderer/tests/sanitizer.test.js`)

- [x] `testSanitizeMermaidSvgRemovesScriptAndEventAttributes` - `Sanitizer.sanitizeMermaidSvg()` strips `<script>` elements and `onclick`/`onload`/`onerror` attributes from SVG input
- [x] `testSanitizeMermaidSvgRemovesForeignObjectAndUnsafeHrefs` - `Sanitizer.sanitizeMermaidSvg()` strips `<foreignObject>` and `<iframe>` elements, and removes `javascript:` URLs from `href`/`xlink:href`
- [x] `testSanitizeMermaidSvgKeepsSafeShapesAndText` - `Sanitizer.sanitizeMermaidSvg()` preserves `<svg>`, `<g>`, `<path>`, `<rect>`, `<text>`, `<tspan>`, and their safe attributes (`fill`, `stroke`, `d`, `transform`, etc.)

### Unit Tests (`WebRenderer/tests/sourcepos.test.js`)

- [x] `testMermaidFencePreservesSourceposRange` - A ```` ```mermaid ```` fence spanning lines 3-7 produces a `.mermaid-block` with `data-sourcepos="3:1-7:3"` (covering the opening fence through the closing fence)

### Integration Tests (`WebRenderer/tests/integration.test.js`)

- [x] `testDocumentWithNoMermaidBlocksRendersNormally` - A document with only regular code blocks produces no `.mermaid-block` elements and `MermaidRenderer.renderBlocks()` resolves immediately without errors
- [x] `testMermaidFenceParticipatesInGutterRangeMatching` - A git change range covering lines inside a Mermaid fence maps to the `.mermaid-block` element for gutter highlighting
- [x] `testFrontMatterOffsetAppliesToMermaidSourcepos` - A document with YAML front matter followed by a Mermaid fence has its `.mermaid-block` `data-sourcepos` correctly offset by the front matter line count

### Integration Tests (`Tests/MarkdownWebViewTests.swift`)

- [x] `testRenderCallRendersMermaidDiagram` - Render a document containing ```` ```mermaid\ngraph TD\n  A-->B\n``` ```` via `MarkdownWebView.render()` and verify the DOM contains a `.mermaid-block` with an `<svg>` child and no JS errors
- [x] `testThemeChangeRerendersMermaidDiagram` - After rendering a Mermaid diagram in light mode, call `setTheme("dark")` and verify the `.mermaid-block` SVG is updated (different fill colors) and the document remains scrollable

### Integration Tests (`Tests/PrintTests.swift`)

- [x] `testPreparePrintKeepsMermaidDiagramVisible` - After `preparePrint()`, verify `.mermaid-block` elements are still in the DOM with `<svg>` children and the SVG colors match the print theme
- [x] `testPreparePrintAppliesLightMermaidBlockChromeFromDarkScreenTheme` - After rendering a Mermaid diagram in dark mode and calling `preparePrint()`, verify `.mermaid-block` switches to the light print background/border palette instead of retaining dark screen chrome
- [x] `testRestoreFromPrintRestoresMermaidScreenTheme` - After `restoreFromPrint()`, verify `.mermaid-block` SVG colors match the original screen theme (not the print theme)

### Manual Verification (Marco)

- [x] Open a Markdown file with at least two Mermaid fences and confirm both diagrams render in light and dark themes
- [x] Toggle the theme (Appearance menu) and confirm both Mermaid diagrams update their colors without a page reload
- [x] Add an intentionally broken Mermaid fence (e.g., `graph INVALID`) and confirm an error message appears above the original source text
- [x] Click the copy button on a rendered Mermaid diagram and paste into a text editor — confirm it contains the original Mermaid source, not SVG markup
- [ ] Open Print Preview for a document with a Mermaid diagram and confirm the diagram is readable and not clipped across page boundaries
- [x] Export a PDF from a document with a Mermaid diagram and confirm the saved PDF includes the diagram with the expected theme
