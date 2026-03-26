# Mermaid Diagram Support

## Meta

- Status: Draft
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
- Invalid Mermaid syntax shows an inline error state and preserves access to the original Mermaid source instead of rendering a blank block or breaking the rest of the document.
- Diagrams follow the current Redmargin light/dark theme and refresh when the theme changes.
- Git gutter indicators and line numbers remain anchored to the correct source line range for the Mermaid fence.
- Print preview and PDF export include Mermaid diagrams and use the active print/export theme rather than stale on-screen colors.
- Users can still copy the Mermaid source from a rendered diagram block.

### Out of scope

- Mermaid editing, zoom/pan controls, or diagram authoring tools
- User-controlled Mermaid `%%{init:}%%` directives, front matter config, custom theme CSS, or HTML labels
- Interactive Mermaid callbacks or link behavior beyond Redmargin's existing document navigation rules
- Remote assets or external diagram extensions/layout engines such as ELK

---

## Technical

### Approach

Bundle the official Mermaid browser build into the existing WebRenderer and keep Mermaid rendering fully app-controlled. Add `WebRenderer/src/vendor/mermaid.min.js` and a new `WebRenderer/src/mermaid.js` wrapper that initializes Mermaid with safe defaults, including `startOnLoad: false`, a strict security level, `htmlLabels: false`, and suppressed built-in error rendering so Redmargin can control the fallback UI. Do not use Mermaid's document-wide auto-run path because Redmargin already owns DOM insertion, scroll preservation, gutter generation, print preparation, and rerender timing.

Modify `WebRenderer/src/index.js` so exact `mermaid` fences emit a `.mermaid-block` wrapper that preserves the fence's `data-sourcepos` and retains escaped source text for copy/error fallback. After Markdown HTML is sanitized and inserted into `#content-container`, render Mermaid blocks sequentially with unique render IDs, sanitize the generated SVG through a dedicated Mermaid/SVG pass in `WebRenderer/src/sanitizer.js`, then regenerate line numbers and gutter markers only after Mermaid layout has finished. Theme changes, print preparation, and PDF export must rerender Mermaid blocks so inline SVG colors match the active screen or print theme. Centralize that lifecycle in shared helpers exposed from `window.App` and called from `src/Views/MarkdownWebView.swift`, then use those helpers from the print/export entry points in `AppMain/DocumentView.swift`, `AppMain/FolderWindowContent.swift`, `AppMain/RemoteDocumentView.swift`, and `src/Printing/PDFExporter.swift`.

### Approach Validation

Official Mermaid docs confirm that site-wide `initialize()` configuration is the intended integration point, and that theme/security options such as `theme`, `securityLevel`, `startOnLoad`, `htmlLabels`, `secure`, and `suppressErrorRendering` are all application-level concerns rather than something Redmargin should leave to document content. The theming docs also confirm that Mermaid ships light, dark, and neutral/base theme paths, which maps cleanly to Redmargin's existing screen and print themes. Relevant references: [Theme Configuration](https://mermaid.js.org/config/theming.html), [MermaidConfig](https://mermaid.js.org/config/setup/mermaid/interfaces/MermaidConfig.html), [Diagram Syntax](https://mermaid.js.org/intro/syntax-reference.html).

Upstream Mermaid issues also reinforce the need for app-controlled sequential rendering. Issue [#4064](https://github.com/mermaid-js/mermaid/issues/4064) and PR [#4142](https://github.com/mermaid-js/mermaid/pull/4142) document async render hazards and queueing problems when `startOnLoad` and manual rendering overlap. Issue [#1601](https://github.com/mermaid-js/mermaid/issues/1601) and PR [#6621](https://github.com/mermaid-js/mermaid/pull/6621) show that fast multi-block rendering can still produce unstable or duplicate SVG IDs. Redmargin should therefore avoid Mermaid auto-scan behavior, render each block sequentially with explicit IDs, and treat Mermaid output as a post-sanitize SVG generation step with its own safety rules. No high-signal end-user feedback specific to native Markdown viewers surfaced beyond upstream Mermaid issue reports, so the product requirements here are driven primarily by Redmargin's existing UX constraints around gutter alignment, line numbers, and print fidelity.

### Risks

| Risk | Mitigation |
| ---- | ---------- |
| Mermaid SVG bypasses the current markdown HTML sanitizer and introduces a new XSS or tracking surface | Lock Mermaid to safe defaults, reject user-controlled Mermaid config in v1, add a dedicated SVG sanitization pass, and keep interactive/remote-asset features out of scope |
| Theme or print rerenders leave stale line numbers or git gutter positions | Await Mermaid completion before calling `LineNumbers.generate()` and `Gutter.update()`, and centralize Mermaid print/export prep and restore in shared helpers |
| Multi-line Mermaid fences lose per-line number alignment because current logic only treats `pre` as a multi-line block | Extend `WebRenderer/src/lineNumbers.js` to treat `.mermaid-block` as a code-like block and add dedicated regression tests |
| Multiple Mermaid blocks collide on generated SVG IDs or race during rapid rerenders | Render blocks sequentially with explicit unique IDs and avoid Mermaid auto-run or parallel `run()` calls |
| Large or invalid diagrams degrade preview responsiveness | Catch render failures per block, fall back to source display for failures, and leave broader performance caps as a separate follow-up if needed |

### Implementation Plan

**Phase 1: Renderer integration**

- [ ] Add `WebRenderer/src/vendor/mermaid.min.js` and create `WebRenderer/src/mermaid.js` with safe Mermaid initialization, sequential rendering helpers, unique block IDs, and source-copy support
- [ ] Update `WebRenderer/src/renderer.html`, `resources/scripts/build.sh`, and `WebRenderer/package.json` so Mermaid assets and renderer tests are bundled and runnable
- [ ] Modify `WebRenderer/src/index.js` so exact `mermaid` fences emit Mermaid placeholders, render after DOM insertion, and rerender when the active theme changes

**Phase 2: Security and layout integration**

- [ ] Extend `WebRenderer/src/sanitizer.js` with a Mermaid/SVG-specific sanitization path instead of widening the existing HTML allowlist to arbitrary SVG
- [ ] Preserve `data-sourcepos` on `.mermaid-block` wrappers and update `WebRenderer/src/lineNumbers.js` so multi-line Mermaid fences distribute height across their full source range
- [ ] Add Mermaid block, error, copy-button, and print pagination styles in `WebRenderer/styles/light.css`, `WebRenderer/styles/dark.css`, and `WebRenderer/styles/print.css`

**Phase 3: Print, PDF, and app hooks**

- [ ] Update `src/Views/MarkdownWebView.swift` to expose shared Mermaid print/export prepare and restore helpers
- [ ] Update `AppMain/DocumentView.swift`, `AppMain/FolderWindowContent.swift`, `AppMain/RemoteDocumentView.swift`, and `src/Printing/PDFExporter.swift` to use the shared Mermaid print/export lifecycle
- [ ] Update `README.md` and `resources/docs/CHANGELOG.md` for the new Mermaid feature once implementation is complete

**Phase 4: Regression coverage**

- [ ] Add renderer coverage in `WebRenderer/tests/mermaid.test.js` for successful render, block-level fallback, theme rerender, and copy-source behavior
- [ ] Add Mermaid SVG security coverage in `WebRenderer/tests/sanitizer.test.js`
- [ ] Add Mermaid source mapping coverage in `WebRenderer/tests/sourcepos.test.js` and `WebRenderer/tests/integration.test.js`
- [ ] Add WKWebView coverage in `Tests/MarkdownWebViewTests.swift` and `Tests/PrintTests.swift` for rendered diagrams, theme switching, and print preparation/restore

---

## Testing

Tests are implementation tasks — the implementer writes and passes each one. Omit test types that don't apply.

### Unit Tests (`WebRenderer/tests/mermaid.test.js`)

- [ ] `testMermaidFenceRendersSvg` - A valid Mermaid fence renders a Mermaid block with sanitized SVG output
- [ ] `testMermaidFenceFallsBackToSourceOnRenderError` - Invalid Mermaid syntax shows an error state and keeps the original source available
- [ ] `testMermaidThemeRerenderUpdatesExistingBlocks` - Mermaid blocks rerender cleanly when the active theme changes
- [ ] `testMermaidCopySourceUsesOriginalFenceText` - Copy action uses the original Mermaid source rather than generated SVG text

### Unit Tests (`WebRenderer/tests/sanitizer.test.js`)

- [ ] `testSanitizeMermaidSvgRemovesScriptAndEventAttributes` - Mermaid-generated SVG cannot keep executable script or inline event handlers
- [ ] `testSanitizeMermaidSvgRemovesForeignObjectAndUnsafeHrefs` - Mermaid SVG cannot keep `foreignObject` nodes or unsafe URL-bearing attributes
- [ ] `testSanitizeMermaidSvgKeepsSafeShapesAndText` - Safe Mermaid SVG elements remain intact after sanitization

### Unit Tests (`WebRenderer/tests/sourcepos.test.js`)

- [ ] `testMermaidFencePreservesSourceposRange` - Mermaid fence wrapper spans the full fenced block line range

### Integration Tests (`WebRenderer/tests/integration.test.js`)

- [ ] `testMermaidFenceParticipatesInGutterRangeMatching` - Changed lines inside a Mermaid fence map to the Mermaid block for gutter highlighting
- [ ] `testFrontMatterOffsetAppliesToMermaidSourcepos` - Mermaid block sourcepos remains correct when front matter is stripped before render

### Integration Tests (`Tests/MarkdownWebViewTests.swift`)

- [ ] `testRenderCallRendersMermaidDiagram` - WKWebView renders a minimal Mermaid diagram without JavaScript errors
- [ ] `testThemeChangeRerendersMermaidDiagram` - Theme changes rerender Mermaid blocks while keeping the document usable

### Integration Tests (`Tests/PrintTests.swift`)

- [ ] `testPreparePrintKeepsMermaidDiagramVisible` - Print preparation keeps Mermaid diagrams in the DOM and applies the print theme
- [ ] `testRestoreFromPrintRestoresMermaidScreenTheme` - Print cleanup restores Mermaid rendering for the normal screen theme

### Manual Verification (Marco)

- [ ] Open a Markdown file with at least two Mermaid fences and confirm both diagrams render in light and dark themes
- [ ] Open Print Preview for a document with a Mermaid diagram and confirm the diagram is readable and not clipped across page boundaries
- [ ] Export a PDF from a document with a Mermaid diagram and confirm the saved PDF includes the diagram with the expected theme
