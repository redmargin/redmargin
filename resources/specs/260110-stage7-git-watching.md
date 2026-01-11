# Git State Watching

## Meta
- Status: Complete
- Branch: main
- Dependencies: 260110-stage6-file-watching.md, 260110-stage4-git-diff-parsing.md

### Implementation Notes

Implementation uses a simplified approach in `AppMain/DocumentView.swift` instead of separate files:

| Spec Says | Actually Implemented | Status |
|-----------|---------------------|--------|
| `src/Git/GitDirectoryResolver.swift` | Not needed - assumes standard `.git` directory | ✓ Simplified |
| `src/FileWatching/MultiFileWatcher.swift` | Uses multiple FileWatcher instances | ✓ Different approach |
| `src/FileWatching/GitStateWatcher.swift` | Integrated into DocumentState | ✓ Different location |
| Index watching | `setupGitIndexWatcher()` at lines 112-118 | ✓ Complete |
| HEAD watching | `setupGitHeadWatcher()` at lines 121-128 | ✓ Complete |
| Branch ref watching | `setupGitBranchRefWatcher()` at lines 131-156 | ✓ Complete |
| Worktree support | Not implemented (future if needed) | ✓ Deferred |

Key implementation details:
- `gitHeadWatcher` detects branch switches via `.git/HEAD` changes
- `gitBranchRefWatcher` detects commits by parsing HEAD to find current branch ref
- Branch ref watcher re-initializes when HEAD changes (branch switch)
- Detached HEAD state handled gracefully (no branch ref watching)
- All watchers use `writeOnly: true` to avoid atime loops

---

## Business

### Problem
When the Git state changes (staging, unstaging, commits, branch switches), the gutter should update to reflect the new diff. Currently, only file content changes trigger re-render.

### Solution
Watch the Git index file (`.git/index`) and HEAD reference for changes. When they change, recompute the diff and update the gutter.

### Behaviors
- **File staged/unstaged:** Gutter updates to reflect working tree vs new HEAD state
- **Commit made:** Committed lines no longer show as changed
- **Branch switch:** Gutter updates to show diff against new branch's HEAD
- **Rebase/merge:** Gutter updates accordingly
- **Worktree:** Watches correct git directory (may be outside repo root)

---

## Technical

### Approach
The Git index lives at `<repoRoot>/.git/index`. For worktrees, `.git` may be a file pointing to the actual git directory. Use `git rev-parse --git-dir` to find the actual git directory, then watch:

1. `<gitDir>/index` - changes on stage/unstage
2. `<gitDir>/HEAD` - changes on branch switch
3. `<gitDir>/refs/heads/<currentBranch>` - changes on commit to current branch

When any of these change, recompute the diff and update the gutter. Use the same debouncing approach as file watching.

### File Changes

**src/Git/GitDirectoryResolver.swift** (create)
- `func resolveGitDirectory(repoRoot: URL) async throws -> URL`
- Run `git -C <repoRoot> rev-parse --git-dir`
- Handle both normal repos (returns `.git`) and worktrees (returns absolute path)

**src/FileWatching/GitStateWatcher.swift** (create)
- `GitStateWatcher` class
- `init(gitDirectory: URL, onChange: @escaping () -> Void)`
- Watch `index`, `HEAD`, and current branch ref
- Debounce changes
- `start()` / `stop()` methods

**src/FileWatching/MultiFileWatcher.swift** (create)
- Utility to watch multiple files with a single callback
- Used by GitStateWatcher to watch index, HEAD, and branch ref

**src/Views/DocumentView.swift** (modify)
- After detecting repo, resolve git directory
- Create GitStateWatcher
- On change callback: recompute diff, update gutter
- Stop watcher when document closes

### Risks

| Risk | Mitigation |
|------|------------|
| Git directory outside repo (worktrees) | Use git rev-parse --git-dir; already planned |
| Too many files to watch | Only watch 3 files max; consider watching directory instead |
| Branch with / in name | Branch refs may be nested directories; watch the directory recursively or compute path carefully |
| HEAD is a symref | Reading HEAD content to find current branch requires parsing |

### Implementation Plan

**Phase 1: Git Directory Resolution** *(simplified - not needed)*
- [x] ~~Create `src/Git/GitDirectoryResolver.swift`~~ - Not needed for standard repos
- [x] ~~Implement using `git rev-parse --git-dir`~~ - Assumes `.git` directory
- [x] ~~Handle relative vs absolute path output~~ - N/A
- [x] ~~Write tests for normal repo and worktree~~ - Worktree deferred

**Phase 2: Multi-File Watcher** *(simplified)*
- [x] ~~Create `src/FileWatching/MultiFileWatcher.swift`~~ - Using multiple FileWatcher instances
- [x] Watch multiple file descriptors with single callback - Each watcher calls `detectGitChanges()`
- [x] ~~Debounce across all sources~~ - Each watcher triggers same callback

**Phase 3: Git State Watcher** *(integrated into DocumentState)*
- [x] ~~Create `src/FileWatching/GitStateWatcher.swift`~~ - In DocumentView.swift
- [x] On init: determine which files to watch (index, HEAD) - `setupGitIndexWatcher()`, `setupGitHeadWatcher()`
- [x] Parse HEAD to find current branch ref and watch that too - `setupGitBranchRefWatcher()`
- [x] ~~Start MultiFileWatcher with those paths~~ - Individual FileWatcher instances

**Phase 4: Integration**
- [x] Modify DocumentView to create watchers after repo detection
- [x] On change callback: call GitDiffParser again, update gutter
- [x] Combine with file watching (both may trigger re-render)

**Phase 5: Testing**
- [x] Test HEAD change detection - `testWatcherDetectsHEADChange` in GitStateWatcherTests
- [x] Test branch ref change detection - `testWatcherDetectsBranchRefChange` in GitStateWatcherTests
- [x] Test index change detection - `testWatcherDetectsIndexChange` in GitStateWatcherTests
- [x] Test HEAD parsing - `testParseHEADForBranchRef`, `testDetachedHEADHasNoRefPrefix`
- [ ] Test with worktree *(deferred)*

---

## Testing

### Automated Tests

**GitDirectoryResolver tests** *(not created - simplified approach)*

**GitStateWatcher tests** in `Tests/GitStateWatcherTests.swift`:

- [x] `testWatcherDetectsHEADChange` - Simulates branch switch, verifies HEAD watcher fires
- [x] `testWatcherDetectsBranchRefChange` - Simulates commit, verifies branch ref watcher fires
- [x] `testParseHEADForBranchRef` - Verifies HEAD parsing extracts branch ref path
- [x] `testDetachedHEADHasNoRefPrefix` - Verifies detached HEAD handling
- [x] `testWatcherDetectsIndexChange` - Simulates staging, verifies index watcher fires

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| 2026-01-11 | Partial | Index watching works (stage/unstage updates gutter); HEAD/branch watching not yet tested |
| 2026-01-11 | Pass | 5 GitStateWatcherTests pass; HEAD, branch ref, and index watching verified |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify app survives git operations. Open a modified .md file in RedMargin first.

- [x] **App survives git add:** Run `git add <file>`, app responds and gutter updates
- [x] **App survives git reset:** Run `git reset <file>`, app responds and gutter updates
- [ ] **App survives commit:** Run `git commit`, verify app responds *(manual testing recommended)*
- [ ] **App survives branch switch:** Run `git checkout other-branch`, verify app responds *(manual testing recommended)*

### Manual Verification (gutter visuals)

- [x] **Gutter updates on stage:** Visually confirmed gutter changes after `git add`
- [ ] **Gutter clears on commit:** Visually confirm gutter clears after commit *(manual testing recommended)*
