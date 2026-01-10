# Git Repo Detection

## Meta
- Status: Draft
- Branch: feature/git-repo-detection
- Dependencies: None (can be built in parallel with app-shell)

---

## Business

### Problem
RedMargin needs to identify whether a Markdown file is inside a Git repository, and if so, find the repository root. This is required before computing Git diffs for the gutter.

### Solution
Shell out to `git rev-parse --show-toplevel` to find the repo root. Handle edge cases: files outside repos, subdirectories, submodules, and worktrees.

### Behaviors
- **File in repo:** App identifies the repo root path
- **File in subdirectory:** Works correctly (e.g., `docs/README.md` in a repo)
- **File outside repo:** App gracefully handles this (no gutter, or empty gutter)
- **Submodule:** Treated as its own repo (submodule's root, not parent's)
- **Worktree:** Correctly identifies the worktree root

---

## Technical

### Approach
Create a `GitRepoDetector` class that takes a file path and returns an optional repo root. Use `Process` to run `git -C <directory> rev-parse --show-toplevel`. Parse stdout for the path; if the command fails (exit code != 0), the file is not in a repo.

For submodules: `--show-toplevel` returns the submodule root when run from within a submodule, which is the correct behavior.

For worktrees: `--show-toplevel` returns the worktree directory, not the main repo. This is correct for our purposes.

### File Changes

**src/Git/GitRepoDetector.swift** (create)
- `GitRepoDetector` class with static or instance methods
- `func detectRepoRoot(forFile fileURL: URL) async throws -> URL?`
- Returns `nil` if not in a repo (don't throw for this case)
- Throws for unexpected errors (git not found, permission denied, etc.)
- Use `Process` with async/await wrapper

**src/Git/GitError.swift** (create)
- `GitError` enum for error cases
- Cases: `gitNotFound`, `permissionDenied`, `unexpectedError(String)`

**src/Utilities/ProcessRunner.swift** (create)
- Reusable async wrapper around `Process`
- `func run(executable: String, arguments: [String], workingDirectory: URL?) async throws -> ProcessResult`
- `ProcessResult` struct with `stdout: String`, `stderr: String`, `exitCode: Int32`

### Risks

| Risk | Mitigation |
|------|------------|
| git not installed on user's machine | Check exit code; show user-friendly message if git not found |
| Very slow on network drives | Set reasonable timeout; consider caching results |
| Symlinks causing confusion | Resolve symlinks before passing to git, or accept git's resolution |

### Implementation Plan

**Phase 1: Process Runner Utility**
- [ ] Create `src/Utilities/ProcessRunner.swift`
- [ ] Implement async `run()` method using `Process` with pipes for stdout/stderr
- [ ] Handle process termination and collect output
- [ ] Write tests for ProcessRunner

**Phase 2: Repo Detection**
- [ ] Create `src/Git/GitError.swift` with error cases
- [ ] Create `src/Git/GitRepoDetector.swift`
- [ ] Implement `detectRepoRoot(forFile:)` using ProcessRunner
- [ ] Return `nil` for non-repo files (exit code != 0)
- [ ] Return the parsed path as URL for repo files

**Phase 3: Edge Case Handling**
- [ ] Test with file in repo root
- [ ] Test with file in nested subdirectory
- [ ] Test with file outside any repo
- [ ] Test with file in submodule
- [ ] Test with file in worktree
- [ ] Handle symlinks (resolve or pass through)

---

## Testing

### Automated Tests

Tests go in `Tests/GitRepoDetectorTests.swift`. These tests require creating temporary Git repos.

**Setup helper:** Create a `GitTestHelper` class in `Tests/Helpers/GitTestHelper.swift` that can:
- Create a temp directory
- Initialize a git repo (`git init`)
- Create files and commit them
- Create submodules
- Clean up after tests

**Tests:**

- [ ] `testDetectsRepoRoot` - Create temp git repo, add a file, call detectRepoRoot, verify it returns the repo root
- [ ] `testDetectsRepoRootFromSubdirectory` - Create repo with `docs/` subdirectory, detect from `docs/file.md`, verify returns repo root (not docs/)
- [ ] `testReturnsNilForNonRepoFile` - Create file in temp dir (no git init), verify detectRepoRoot returns nil
- [ ] `testHandlesSubmodule` - Create repo A with submodule B, detect from file in B, verify returns B's root (not A's)
- [ ] `testHandlesMissingFile` - Call with path to non-existent file, verify graceful handling (nil or specific error)
- [ ] `testPathContainsSpaces` - Create repo at path with spaces, verify detection works
- [ ] `testPathContainsUnicode` - Create repo at path with Unicode chars, verify detection works

**ProcessRunner tests** in `Tests/ProcessRunnerTests.swift`:

- [ ] `testRunsSimpleCommand` - Run `echo hello`, verify stdout is "hello\n"
- [ ] `testCapturesStderr` - Run command that writes to stderr, verify it's captured
- [ ] `testReturnsExitCode` - Run `false` (or command that fails), verify exitCode is non-zero
- [ ] `testHandlesWorkingDirectory` - Run `pwd` in a specific directory, verify output matches

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### Verification

This spec is pure backend logic with no UI. All verification is covered by automated tests above. No manual or MCP verification needed.
