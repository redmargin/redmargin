# Checkbox & Anchor Issues - 2025-01-20

## Problems

### 1. Remote Checkbox Toggle Reverts
When clicking a checkbox in a remote (SSH) file, it visually toggles then reverts back.

**Root cause hypothesis:** Race condition between optimistic UI update and file watcher. The file watcher fires during/after write and reads old content before write completes, reverting the state.

### 2. Anchor Links Not Working
Clicking internal links like `[Jump to Section](#section-one)` does nothing.

**Root cause hypothesis:** Initially the navigation policy blocked fragment URLs. Fixed to use JavaScript `scrollIntoView()` instead of allowing WebKit navigation (which reloads the page).

## Changes Made

### Remote Checkbox (RemoteDocumentState.swift)
- Added `isWritingFile` flag (line 28)
- Added guard in `reloadContent()` to skip during writes (lines 208-212)
- Set flag before write, clear after (lines 339-347)

### Local Checkbox (DocumentState.swift)
- Added `isWritingFile` flag (line 17)
- Added guard in `reloadContent()` (lines 53-58)
- Changed order: write to disk FIRST, then update content (lines 194-200)

### Anchor Links (MarkdownWebView.swift)
- Changed from `decisionHandler(.allow)` to using JavaScript `scrollIntoView()` (lines 304-329)
- Reason: Allowing navigation caused page reload instead of scroll
- Added escaping for fragment identifiers (lines 312-314) to prevent JavaScript injection with special characters

## Code Review Summary

Reviewed all three implementations. The `isWritingFile` flag pattern is correctly implemented:

1. **RemoteDocumentState**: Flag set synchronously on MainActor before async Task starts, cleared in defer after Task completes. The `reloadContent()` guard correctly skips during writes.

2. **DocumentState**: Same pattern. Additionally, writes to disk first before updating in-memory content.

3. **MarkdownWebView**: Uses JavaScript `scrollIntoView()` with proper escaping for fragment IDs.

## Not Tested

- Remote checkbox toggle (cannot automate WKWebView clicks on remote server content)
- Anchor link scrolling (same limitation)

## Manual Testing Required

1. Open a local markdown file with checkboxes - click checkbox, verify it toggles and persists
2. Open a remote (SSH) file with checkboxes - click checkbox, verify it toggles and persists (no revert)
3. Open a file with anchor links - click `[link](#section)`, verify smooth scroll to section
