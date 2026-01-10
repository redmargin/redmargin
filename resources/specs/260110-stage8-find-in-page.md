# Find in Page

## Meta
- Status: Draft
- Branch: feature/find-in-page
- Dependencies: 260110-stage2-webview-renderer.md

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

**src/App/RedMarginApp.swift** (modify)
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
- [ ] Create `src/Views/FindBar.swift` with TextField and buttons
- [ ] Add state for search text and match count display
- [ ] Style to look native (system appearance)
- [ ] Test UI standalone

**Phase 2: WebView Find Integration**
- [ ] Add find methods to MarkdownWebView
- [ ] Implement `find(text:)` using `WKWebView.find(_:configuration:)`
- [ ] Implement `findNext()` and `findPrevious()`
- [ ] Implement `clearFind()` to dismiss highlights

**Phase 3: Document Integration**
- [ ] Add find bar state to DocumentView
- [ ] Toggle visibility with Cmd+F
- [ ] Wire search text changes to WebView find
- [ ] Wire next/previous buttons to WebView methods

**Phase 4: Keyboard Shortcuts**
- [ ] Escape closes find bar
- [ ] Enter in TextField triggers find/findNext
- [ ] Shift+Enter triggers findPrevious
- [ ] Cmd+G / Cmd+Shift+G for next/previous

**Phase 5: Menu Integration**
- [ ] Add Edit > Find menu items to RedMarginApp
- [ ] Wire to focused window's find functionality
- [ ] Ensure keyboard shortcuts match menu items

---

## Testing

### Automated Tests

Find functionality is primarily UI-driven. Unit tests focus on the integration:

**MarkdownWebView tests** in `Tests/FindTests.swift`:

- [ ] `testFindHighlightsMatches` - Load content with "test" appearing 3 times, call find("test"), verify completion reports 3 matches
- [ ] `testFindNoMatches` - Search for text not in document, verify 0 matches reported
- [ ] `testFindNextCyclesToFirst` - At last match, call findNext, verify it cycles to first
- [ ] `testFindPreviousFromFirst` - At first match, call findPrevious, verify it cycles to last
- [ ] `testClearFindRemovesHighlights` - Call find, then clearFind, verify highlights removed

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify find bar behavior. Open a .md file with searchable content in RedMargin first.

- [ ] **Edit > Find menu exists:** `find_elements_in_app("RedMargin", "$..[?(@.role=='menuItem' && @.title=='Find…')]")` finds menu item
- [ ] **Find bar appears on Cmd+F:** Trigger Cmd+F (or click menu), then `find_elements_in_app("RedMargin", "$..[?(@.role=='textField')]")` finds search text field
- [ ] **Can type in find bar:** `type_text_to_element_by_selector("$..[?(@.role=='textField')]", "search term")` succeeds
- [ ] **Match count displayed:** `find_elements_in_app("RedMargin", "$..[?(@.role=='staticText')]")` includes match count text (e.g., "3 of 10")
- [ ] **Next/Previous buttons exist:** `find_elements_in_app("RedMargin", "$..[?(@.role=='button')]")` includes navigation buttons
- [ ] **Click next button:** `click_element_by_selector("$..[?(@.role=='button' && @.title=='Next')]")` succeeds
- [ ] **Find bar closes on Escape:** After pressing Escape, text field no longer present

### Manual Verification (WebView highlights)

- [ ] **Match highlighting:** Visually confirm matches highlighted in WebView (not accessible via MCP)
- [ ] **Case insensitive:** Search "test" matches "Test" and "TEST"
