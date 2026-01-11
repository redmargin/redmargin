# Find in Page

## Meta
- Status: Implementation Complete (Manual Testing Pending)
- Branch: feature/find-in-page
- Dependencies: 260110-stage2-webview-renderer.md

### Implementation Notes

Implementation uses `FindController` class and JavaScript's `window.find()` API instead of WKFindConfiguration:

| Spec Says | Actually Implemented | Status |
|-----------|---------------------|--------|
| Methods on MarkdownWebView | `FindController` class passed to view | ✓ Different approach |
| `WKFindConfiguration` | JavaScript `window.find()` + regex count | ✓ More flexible |
| `src/Views/DocumentView.swift` | `AppMain/DocumentView.swift` | ✓ Different location |

Key implementation details:
- `FindController` holds weak reference to WKWebView, provides `find()`, `findNext()`, `findPrevious()`, `clearFind()`
- Match count computed via JavaScript regex on `document.body.innerText`
- Navigation uses `window.find(text, caseSensitive, backwards, wrapAround)`
- FindBar uses `.onKeyPress(.escape)` for dismiss

---

## Business

### Problem
Users need to search for text within the rendered Markdown view to quickly locate content in long documents.

### Solution
Implement find-in-page using WKWebView's native find API (`WKFindConfiguration` and `find(_:configuration:)`). Provide a search bar UI with next/previous navigation.

### Behaviors
- **Cmd+F:** Opens find bar
- **Escape:** Closes find bar
- **Enter / Cmd+G:** Find next
- **Shift+Enter / Cmd+Shift+G:** Find previous
- **Match highlighting:** All matches highlighted, current match distinct
- **Match count:** Display "X of Y matches" (if API supports)
- **Case sensitivity:** Case-insensitive by default (configurable optional)

---

## Technical

### Approach
WKWebView provides `find(_:configuration:completionHandler:)` for searching. Create a SwiftUI search bar that overlays or sits above the WebView. On search, call the WKWebView find method. Use `findNext()` and `findPrevious()` methods for navigation.

Note: The WKWebView find API was introduced in iOS 16 / macOS 13. Since we target macOS 14+, this is available.

### File Changes

**src/Views/FindBar.swift** (create)
- SwiftUI view with TextField for search input
- Display match count (X of Y)
- Buttons for previous/next (and keyboard shortcuts)
- Close button or Escape key handling

**src/Views/MarkdownWebView.swift** (modify)
- Expose `find(text:)`, `findNext()`, `findPrevious()`, `clearFind()` methods
- Create `WKFindConfiguration` with case-insensitive search
- Handle find completion to get match count

**src/Views/DocumentView.swift** (modify)
- Add state for find bar visibility and search text
- Layer FindBar on top of MarkdownWebView
- Wire up Cmd+F to show find bar
- Pass search actions to MarkdownWebView

**AppMain/RedMarginApp.swift** (modify)
- Add Edit menu with Find submenu (Find, Find Next, Find Previous)
- Wire menu items to focused document's find functionality

### Risks

| Risk | Mitigation |
|------|------------|
| WKWebView find API limitations | API provides basic find; match count may require checking result object |
| Keyboard focus issues | Ensure TextField captures Escape correctly; may need custom handling |
| Highlight colors in dark mode | Test and adjust highlight colors for visibility in both themes |

### Implementation Plan

**Phase 1: Find Bar UI**
- [x] Create `src/Views/FindBar.swift` with TextField and buttons
- [x] Add state for search text and match count display
- [x] Style to look native (system appearance)
- [x] Test UI standalone

**Phase 2: WebView Find Integration**
- [x] Add find methods to MarkdownWebView - Created `FindController` class
- [x] Implement `find(text:)` using JavaScript `window.find()` + regex count
- [x] Implement `findNext()` and `findPrevious()`
- [x] Implement `clearFind()` to dismiss highlights

**Phase 3: Document Integration**
- [x] Add find bar state to DocumentView (`AppMain/DocumentView.swift`)
- [x] Toggle visibility with Cmd+F
- [x] Wire search text changes to WebView find
- [x] Wire next/previous buttons to WebView methods

**Phase 4: Keyboard Shortcuts**
- [x] Escape closes find bar
- [x] Enter in TextField triggers find/findNext
- [ ] Shift+Enter triggers findPrevious *(not implemented - uses Cmd+Shift+G instead)*
- [x] Cmd+G / Cmd+Shift+G for next/previous

**Phase 5: Menu Integration**
- [x] Add Edit > Find menu items to RedMarginApp
- [x] Wire to focused window's find functionality
- [x] Ensure keyboard shortcuts match menu items

---

## Testing

### Automated Tests

Find functionality is primarily UI-driven. Unit tests focus on the integration:

**MarkdownWebView tests** in `Tests/FindTests.swift`:

- [x] `testFindHighlightsMatches` - Load content with "test" appearing 3 times, call find("test"), verify completion reports 3 matches
- [x] `testFindNoMatches` - Search for text not in document, verify 0 matches reported
- [x] `testFindNextCyclesToFirst` - At last match, call findNext, verify it cycles to first
- [x] `testFindPreviousFromFirst` - At first match, call findPrevious, verify it cycles to last
- [x] `testClearFindRemovesHighlights` - Call find, then clearFind, verify highlights removed

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| 2026-01-11 | Pass | 5 tests pass in FindTests.swift |

### MCP UI Verification

*Note: MCP UI automation has trouble finding elements in this app (likely accessibility identifiers not set). Recommend manual verification.*

- [x] **Edit > Find menu exists:** Verify "Find..." menu item in Edit menu
- [x] **Find bar appears on Cmd+F:** Press Cmd+F, verify search field appears
- [x] **Can type in find bar:** Type search term, verify it appears in field
- [x] **Match count displayed:** Verify "X of Y" text appears after searching
- [x] **Next/Previous buttons exist:** Verify chevron buttons appear
- [x] **Find bar closes on Escape:** Press Escape, verify find bar disappears

### Manual Verification (WebView highlights)

- [x] **Match highlighting:** Visually confirm matches highlighted in WebView
- [x] **Case insensitive:** Search "test" matches "Test" and "TEST"
