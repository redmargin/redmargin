# File Watching

## Meta
- Status: Draft
- Branch: feature/file-watching
- Dependencies: 260110-stage2-webview-renderer.md

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

**Phase 1: Debouncer Utility**
- [ ] Create `src/FileWatching/Debouncer.swift`
- [ ] Implement with DispatchWorkItem for cancellable delayed execution
- [ ] Write tests for debouncer behavior

**Phase 2: File Watcher**
- [ ] Create `src/FileWatching/FileWatcher.swift`
- [ ] Implement using DispatchSource.makeFileSystemObjectSource
- [ ] Watch for `.write` events
- [ ] Integrate Debouncer for change callback
- [ ] Implement start/stop lifecycle

**Phase 3: Integration**
- [ ] Modify DocumentView to create FileWatcher on appear
- [ ] Implement change callback: re-read content, call render
- [ ] Stop watcher on disappear/document close
- [ ] Modify MarkdownDocument to support re-reading from disk

**Phase 4: Scroll Preservation**
- [ ] Before re-render: query scroll position via JS
- [ ] After re-render: restore scroll position via JS
- [ ] Add JS methods: `window.App.getScrollPosition()` and `window.App.setScrollPosition(y)`

**Phase 5: Error Handling**
- [ ] Handle file deletion: show "File not found" in view
- [ ] Handle file rename: attempt to re-watch, or show error
- [ ] Handle read errors: show error state, don't crash

---

## Testing

### Automated Tests

**Debouncer tests** in `Tests/DebouncerTests.swift`:

- [ ] `testDebouncerCallsAfterDelay` - Schedule call, verify it executes after delay
- [ ] `testDebouncerCancelsPrevious` - Schedule two calls rapidly, verify only second executes
- [ ] `testDebouncerRespectsDelay` - Schedule call, verify it doesn't execute before delay
- [ ] `testDebouncerMultipleBursts` - Rapid calls, pause, rapid calls, verify two executions total

**FileWatcher tests** in `Tests/FileWatcherTests.swift`:

- [ ] `testWatcherDetectsWrite` - Create temp file, start watcher, write to file, verify callback fired
- [ ] `testWatcherDebounces` - Write multiple times rapidly, verify callback fires once (after debounce)
- [ ] `testWatcherStopPreventsCallback` - Start watcher, stop it, write to file, verify no callback
- [ ] `testWatcherHandlesDeletedFile` - Start watcher, delete file, verify appropriate handling (no crash)
- [ ] `testWatcherCanRestart` - Start, stop, start again, verify still works

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify app behavior during file changes. Open a test .md file in RedMargin first.

- [ ] **App responds after file edit:** Modify the file externally (`echo "new content" >> file.md`), then `find_elements_in_app("RedMargin", "$..[?(@.role=='window')]")` - app still responds, window exists
- [ ] **App survives rapid saves:** Write to file 5 times rapidly via bash, verify app window still present
- [ ] **App survives file deletion:** Delete file, verify app doesn't crash (`list_running_applications` still shows RedMargin)

### Scripted Verification

Create `Tests/Scripts/test-file-watching.sh` to automate:
```bash
# 1. Open test file in RedMargin (manually or via `open -a RedMargin file.md`)
# 2. Modify file externally
# 3. Check app is responsive via MCP
# 4. Repeat with rapid saves
```

### Manual Verification

- [ ] **Scroll preservation:** Scroll to middle, edit file externally, verify scroll approximately preserved (hard to automate)
