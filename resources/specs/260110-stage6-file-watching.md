# File Watching

## Meta
- Status: Complete
- Branch: main (implemented during Stage 5)
- Dependencies: 260110-stage2-webview-renderer.md

### Implementation Notes

The implementation differs from the original spec but achieves all goals:

| Spec Says | Actually Implemented | Status |
|-----------|---------------------|--------|
| `src/FileWatching/Debouncer.swift` | Not needed - DispatchSource coalesces events, JS uses `setTimeout` | ✓ Different approach |
| `src/FileWatching/FileWatcher.swift` | `FileWatcher` class in `AppMain/DocumentView.swift:7-85` | ✓ Different location |
| Modify `src/Views/DocumentView.swift` | `DocumentState` class in `AppMain/DocumentView.swift:87-247` | ✓ Different pattern |
| Modify `src/App/MarkdownDocument.swift` | Uses `DocumentState.reloadContent()` instead | ✓ Different pattern |
| Scroll preservation via JS | `WebRenderer/src/scrollPosition.js` | ✓ Complete |
| Handle atomic writes | `restartWatching()` at line 59-77 | ✓ Complete |
| Handle rename/delete | Lines 45-49, restarts watcher | ✓ Complete |
| Git index watching | `setupGitIndexWatcher()` at lines 110-117 | ✓ Bonus (Stage 7) |
| Tests | `Tests/FileWatcherTests.swift` - 4 tests | ✓ Complete |

Key differences:
- No separate Debouncer class needed - DispatchSource naturally coalesces rapid events
- FileWatcher embedded in DocumentView.swift rather than separate file
- Uses DocumentState pattern with @StateObject for SwiftUI integration
- Git index watching already implemented (partial Stage 7)

---

## Business

### Problem
When the user edits a Markdown file in their editor, RedMargin should automatically re-render the updated content without requiring manual refresh.

### Solution
Use FSEvents (or DispatchSource) to watch the open file for changes. When the file is modified, re-read and re-render with debouncing to avoid thrashing during rapid saves.

### Behaviors
- **File modified:** Content re-renders within ~200ms of save (after debounce)
- **File renamed:** App follows the file (if possible) or shows error
- **File deleted:** App shows appropriate state (empty or error message)
- **Rapid saves:** Debounce prevents excessive re-renders (coalesce events within 150-300ms window)
- **Scroll position:** Preserved across re-renders when possible

---

## Technical

### Approach
Use `DispatchSource.makeFileSystemObjectSource` to watch the file for `.write` events. When an event fires, schedule a debounced re-render. Cancel any pending re-render if a new event arrives within the debounce window.

For renamed/deleted files: the file descriptor becomes invalid. Detect this and either:
- Try to re-establish watch at the same path (file recreated)
- Show "file not found" state

Store current scroll position before re-render and restore after.

### File Changes

**src/FileWatching/FileWatcher.swift** (create)
- `FileWatcher` class using DispatchSource
- `init(url: URL, onChange: @escaping () -> Void)`
- `start()` / `stop()` methods
- Debounce logic with configurable delay (default 200ms)
- Handle file deletion/rename (source cancel event)

**src/FileWatching/Debouncer.swift** (create)
- Generic `Debouncer` utility class
- `func call(_ block: @escaping () -> Void)`
- Cancels previous pending call if within window
- Configurable delay

**src/Views/DocumentView.swift** (modify)
- Create FileWatcher when document opens
- On change callback: re-read file content, re-render
- Stop watcher when document closes
- Save/restore scroll position around re-renders

**src/App/MarkdownDocument.swift** (modify)
- Add method to re-read file content from disk
- Update content property and notify observers

### Risks

| Risk | Mitigation |
|------|------------|
| File locked during write | Use retry with short delay if read fails; most editors write atomically |
| Too many events | Debouncing handles this; tune debounce delay based on testing |
| Memory leak from watcher | Ensure watcher is stopped and released when document closes |
| Scroll position lost | Cache scroll position before re-render, restore after; accept some drift for large changes |

### Implementation Plan

**Phase 1: Debouncer Utility** *(skipped - not needed)*
- [x] ~~Create `src/FileWatching/Debouncer.swift`~~ - DispatchSource coalesces events naturally
- [x] ~~Implement with DispatchWorkItem~~ - Not needed
- [x] ~~Write tests for debouncer behavior~~ - Not needed

**Phase 2: File Watcher**
- [x] Create FileWatcher class (in `AppMain/DocumentView.swift:7-85`)
- [x] Implement using DispatchSource.makeFileSystemObjectSource
- [x] Watch for `.write`, `.rename`, `.delete` events
- [x] Implement start/stop lifecycle via init/deinit

**Phase 3: Integration**
- [x] DocumentState creates FileWatcher on init (`setupFileWatcher()`)
- [x] Change callback: `reloadContent()` re-reads file, triggers re-render
- [x] Watcher stopped via deinit when DocumentState released
- [x] Content update via `@Published var content` triggers SwiftUI update

**Phase 4: Scroll Preservation**
- [x] Scroll position saved via `WebRenderer/src/scrollPosition.js`
- [x] Position restored on re-render via `ScrollPosition.restore()`
- [x] Uses webkit message handlers for Swift ↔ JS communication

**Phase 5: Error Handling**
- [x] Handle file deletion: watcher detects `.delete`, attempts restart
- [x] Handle atomic writes (rename): `restartWatching()` reopens file descriptor
- [x] Read errors: logged, content not updated (no crash)

---

## Testing

### Automated Tests

**Debouncer tests** *(skipped - no separate Debouncer class)*

**FileWatcher tests** in `Tests/FileWatcherTests.swift`:

- [x] `testDispatchSourceDetectsWrite` - Write to file, verify event fired
- [x] `testDispatchSourceDetectsAtomicWrite` - Atomic write, verify event fired
- [x] `testDispatchSourceDetectsMultipleWrites` - Rapid writes, verify events detected
- [x] `testDispatchSourceAfterAtomicWriteNeedsRestart` - Demonstrates fd becomes stale after atomic write

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| 2026-01-11 | Pass | 4 FileWatcher tests pass; verified in Stage 5 testing |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify app behavior during file changes. Open a test .md file in RedMargin first.

- [x] **App responds after file edit:** Verified during Stage 5 testing
- [x] **App survives rapid saves:** Verified during Stage 5 testing
- [x] **App survives file deletion:** Verified - watcher attempts restart

### Scripted Verification

*(Not created - manual verification sufficient)*

### Manual Verification

- [x] **Scroll preservation:** Scroll to middle, edit file externally, scroll approximately preserved
