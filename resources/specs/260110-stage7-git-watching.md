# Git State Watching

## Meta
- Status: Draft
- Branch: feature/git-watching
- Dependencies: 260110-stage6-file-watching.md, 260110-stage4-git-diff-parsing.md

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

**Phase 1: Git Directory Resolution**
- [ ] Create `src/Git/GitDirectoryResolver.swift`
- [ ] Implement using `git rev-parse --git-dir`
- [ ] Handle relative vs absolute path output
- [ ] Write tests for normal repo and worktree

**Phase 2: Multi-File Watcher**
- [ ] Create `src/FileWatching/MultiFileWatcher.swift`
- [ ] Watch multiple file descriptors with single callback
- [ ] Debounce across all sources

**Phase 3: Git State Watcher**
- [ ] Create `src/FileWatching/GitStateWatcher.swift`
- [ ] On init: determine which files to watch (index, HEAD)
- [ ] Optionally parse HEAD to find current branch ref and watch that too
- [ ] Start MultiFileWatcher with those paths

**Phase 4: Integration**
- [ ] Modify DocumentView to create GitStateWatcher after repo detection
- [ ] On change callback: call GitDiffParser again, update gutter
- [ ] Combine with file watching (both may trigger re-render)

**Phase 5: Testing Edge Cases**
- [ ] Test with worktree
- [ ] Test branch switch (`git checkout`)
- [ ] Test stage/unstage
- [ ] Test commit

---

## Testing

### Automated Tests

**GitDirectoryResolver tests** in `Tests/GitDirectoryResolverTests.swift`:

- [ ] `testResolvesNormalRepo` - Normal repo returns `<repoRoot>/.git`
- [ ] `testResolvesWorktree` - Worktree returns the absolute gitdir path

**GitStateWatcher tests** in `Tests/GitStateWatcherTests.swift`:

- [ ] `testWatcherDetectsIndexChange` - Create repo, start watcher, stage a file, verify callback
- [ ] `testWatcherDetectsCommit` - Start watcher, make commit, verify callback
- [ ] `testWatcherDetectsBranchSwitch` - Start watcher, checkout different branch, verify callback
- [ ] `testWatcherDebounces` - Multiple rapid git operations, verify single callback after debounce

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify app survives git operations. Open a modified .md file in RedMargin first.

- [ ] **App survives git add:** Run `git add <file>`, then `find_elements_in_app("RedMargin", "$..[?(@.role=='window')]")` - app responds
- [ ] **App survives git reset:** Run `git reset <file>`, verify app responds
- [ ] **App survives commit:** Run `git commit`, verify app responds
- [ ] **App survives branch switch:** Run `git checkout other-branch`, verify app responds

### Scripted Verification

Create `Tests/Scripts/test-git-watching.sh` to automate:
```bash
# 1. Open test file in RedMargin
# 2. Run git add, verify app responsive via MCP
# 3. Run git reset, verify app responsive
# 4. Make commit, verify app responsive
# 5. Switch branch, verify app responsive
```

### Manual Verification (gutter visuals)

- [ ] **Gutter updates on stage:** Visually confirm gutter changes after `git add`
- [ ] **Gutter clears on commit:** Visually confirm gutter clears after commit
