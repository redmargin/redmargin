# Git Gutter

## Meta
- Status: Draft
- Branch: feature/git-gutter
- Dependencies: 260110-stage2-webview-renderer.md, 260110-stage4-git-diff-parsing.md

---

## Business

### Problem
This is the core feature of RedMargin. Users need to see which lines in the rendered Markdown have been changed (added/modified) or deleted compared to HEAD, displayed as a visual gutter alongside the content.

### Solution
Add a left gutter overlay in the WebView that shows colored bars for changed lines. Map source line ranges from Git to rendered DOM elements using `data-sourcepos` attributes. Keep the gutter synchronized with scrolling.

### Behaviors
- **Changed lines (added/modified):** Blue vertical bar in the gutter alongside the rendered block
- **Added lines (pure addition, optional distinction):** Green vertical bar (or blue if not distinguishing)
- **Deleted lines:** Small red triangle/marker at the anchor point
- **Scrolling:** Gutter markers scroll with content, staying aligned
- **Resize:** Gutter repositions correctly when window resizes
- **No repo:** Gutter hidden or empty (configurable in preferences spec)

---

## Technical

### Approach
The gutter is drawn in JavaScript as absolutely-positioned `<div>` elements within a fixed gutter container. After Markdown renders:

1. Query all elements with `data-sourcepos`
2. Parse sourcepos into `[startLine, endLine]` for each element
3. Check if element's line range overlaps with any `changedRange`
4. For overlapping elements: compute bounding rect, create gutter marker div at that Y position/height
5. For `deletedAnchors`: find the element at/after that line, place a deletion marker at its top

On scroll: update gutter marker positions using cached element references (no DOM re-query).
On resize: recompute positions (elements may reflow).

### Gutter Layout
- Gutter container: fixed-position div, left side, full height of viewport
- Gutter width: ~4px for the colored bar
- Gutter markers: absolutely positioned within container
- Colors: CSS variables for easy theming

### File Changes

**WebRenderer/src/gutter.js** (create)
- `Gutter` class managing gutter state and rendering
- `update(changedRanges, deletedAnchors)` - compute and draw markers
- `onScroll()` - reposition markers based on current scroll
- `onResize()` - recompute all positions
- Cache element references and their sourcepos ranges

**WebRenderer/src/sourcepos-map.js** (create)
- `SourcePosMap` class that maps source lines to DOM elements
- `build()` - query all `[data-sourcepos]` elements, parse and index them
- `getElementsForLineRange(start, end)` - return elements overlapping the range
- `getElementAtOrAfterLine(line)` - for deletion anchors

**WebRenderer/src/index.js** (modify)
- Import and initialize Gutter
- After rendering Markdown, call `gutter.update(changedRanges, deletedAnchors)`
- Set up scroll and resize event listeners

**WebRenderer/styles/gutter.css** (create)
- `.gutter-container` - fixed positioning, left side
- `.gutter-marker` - the colored bar for changes
- `.gutter-marker--added` - green color (if distinguishing)
- `.gutter-marker--modified` - blue color
- `.gutter-marker--deleted` - red triangle/arrow indicator
- CSS variables for colors (overridden by theme)

**WebRenderer/styles/light.css** (modify)
- Add gutter color variables for light theme

**WebRenderer/styles/dark.css** (modify)
- Add gutter color variables for dark theme

**src/Views/MarkdownWebView.swift** (modify)
- Update `render()` to pass `changedRanges` and `deletedAnchors` to JS
- After repo detection and diff parsing, include change data in render call

**src/Views/DocumentView.swift** (modify)
- Integrate GitRepoDetector and GitDiffParser
- On document load: detect repo, compute diff, pass to WebView
- Handle case where file is not in repo (no change data)

### Risks

| Risk | Mitigation |
|------|------------|
| Gutter drifts from content on scroll | Use scroll event throttling; ensure gutter and content scroll containers are synchronized |
| Elements without sourcepos | Some inline elements won't have it; only mark block elements, which is correct |
| Overlapping elements | If a heading and its following paragraph both overlap a change, both get markers; this is expected |
| Performance with many markers | Use document fragment for batch DOM updates; consider virtualizing for very long docs |
| Deleted at EOF | Handle specially: anchor to last element if deletedAnchor > last line |

### Implementation Plan

**Phase 1: Gutter Container**
- [ ] Create `WebRenderer/styles/gutter.css` with container and marker styles
- [ ] Add gutter container div to `renderer.html`
- [ ] Verify gutter container appears on left side of viewport

**Phase 2: SourcePos Mapping**
- [ ] Create `WebRenderer/src/sourcepos-map.js`
- [ ] Implement `build()` to query and parse all sourcepos attributes
- [ ] Implement `getElementsForLineRange(start, end)` with overlap detection
- [ ] Implement `getElementAtOrAfterLine(line)` for deletion anchors
- [ ] Write JS unit tests for overlap logic

**Phase 3: Gutter Rendering**
- [ ] Create `WebRenderer/src/gutter.js`
- [ ] Implement `update(changedRanges, deletedAnchors)`
- [ ] For each changed range: find overlapping elements, create markers
- [ ] For each deleted anchor: find target element, create deletion marker
- [ ] Add markers to gutter container

**Phase 4: Scroll Synchronization**
- [ ] Implement `onScroll()` to reposition markers
- [ ] Cache element references on initial render
- [ ] Use `getBoundingClientRect()` on scroll to get current positions
- [ ] Throttle scroll handler (requestAnimationFrame)

**Phase 5: Resize Handling**
- [ ] Implement `onResize()` to recompute positions
- [ ] Call on window resize event
- [ ] Debounce resize handler

**Phase 6: Swift Integration**
- [ ] Modify `DocumentView.swift` to call GitRepoDetector on document load
- [ ] If in repo: call GitDiffParser to get changes
- [ ] Pass changedRanges and deletedAnchors to MarkdownWebView.render()
- [ ] Handle non-repo case (don't pass change data, gutter stays empty)

**Phase 7: Polish**
- [ ] Add color variables to light.css and dark.css
- [ ] Test gutter appearance in both themes
- [ ] Test with various file sizes and change patterns

---

## Testing

### Automated Tests

**JavaScript tests** in `WebRenderer/tests/`:

- [ ] `testSourcePosMapBuild` - Render Markdown, call build(), verify map contains all block elements
- [ ] `testSourcePosMapOverlapFull` - Element lines 5-10, range 5-10, verify it's returned
- [ ] `testSourcePosMapOverlapPartial` - Element lines 5-10, range 7-8, verify it's returned
- [ ] `testSourcePosMapNoOverlap` - Element lines 5-10, range 15-20, verify not returned
- [ ] `testSourcePosMapMultipleElements` - Multiple elements, range overlaps two, verify both returned
- [ ] `testDeletionAnchorMiddle` - Deletion at line 10, verify correct element found
- [ ] `testDeletionAnchorStart` - Deletion at line 1, verify first element found
- [ ] `testDeletionAnchorEnd` - Deletion beyond last line, verify last element found
- [ ] `testGutterMarkerCount` - Render with 3 changed ranges, verify 3+ markers created
- [ ] `testGutterMarkerPosition` - Render with change on line 5, verify marker Y position matches element top
- [ ] `testGutterDeletionMarker` - Render with deletion anchor, verify deletion marker exists
- [ ] `testGutterScrollUpdate` - Scroll container, verify marker positions update

**Integration tests** (Swift, using WebView):

- [ ] `testGutterAppearsForChangedFile` - Load file with known changes, verify gutter markers present in DOM
- [ ] `testGutterEmptyForCleanFile` - Load unchanged file, verify no gutter markers
- [ ] `testGutterEmptyForNonRepoFile` - Load file outside repo, verify no gutter markers

### Test Fixtures

Create `Tests/Fixtures/gutter-test-repo/`:
- Initialize as git repo
- Commit a base `test.md` with numbered lines (Line 1, Line 2, ... Line 20)
- In working tree: modify lines 5-7, add lines at end, delete lines 12-14
- This provides a known diff for testing

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify app behavior. Gutter rendering is inside WebView (not accessible via accessibility APIs), so gutter visuals rely on JS tests + manual spot-check.

- [ ] **App window exists:** `find_elements_in_app("RedMargin", "$..[?(@.role=='window')]")` returns window
- [ ] **No crash on scroll:** Use MCP to verify app still responds after scrolling (window still present)
- [ ] **No crash on resize:** Resize window, verify app still responds

### Manual Verification (WebView internals)

- [ ] **Gutter appears:** Open modified .md file, visually confirm colored bars on left
- [ ] **Scroll alignment:** Scroll and confirm gutter markers stay aligned
- [ ] **Deletion marker:** Delete a paragraph, confirm red marker appears
- [ ] **Inspect DOM:** Safari Web Inspector shows `.gutter-marker` elements with correct positions
