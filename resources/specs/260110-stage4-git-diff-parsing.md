# Git Diff Parsing

## Meta
- Status: Complete
- Branch: feature/git-diff-parsing
- Dependencies: 260110-stage3-git-repo-detection.md (uses ProcessRunner and GitError)

---

## Business

### Problem
RedMargin needs to know which lines in a Markdown file have been added, modified, or deleted compared to the last commit (HEAD). This information drives the gutter display.

### Solution
Run `git diff --unified=0 HEAD -- <file>` and parse the unified diff output to extract changed line ranges. Produce a structured result with `changedRanges` (added/modified lines) and `deletedAnchors` (where deleted lines were).

### Behaviors
- **Modified lines:** Lines that exist in both HEAD and working tree but differ
- **Added lines:** Lines that exist in working tree but not in HEAD
- **Deleted lines:** Lines that existed in HEAD but not in working tree (represented as anchor points)
- **Untracked files:** All lines treated as "added"
- **Clean files:** Empty change set

---

## Technical

### Approach
Use `git diff --unified=0 HEAD -- <relativePath>` to get minimal diff output. Parse hunk headers in the format `@@ -oldStart,oldCount +newStart,newCount @@`.

For each hunk:
- If `newCount > 0`: add `[newStart, newStart + newCount - 1]` to `changedRanges`
  - If `oldCount == 0`: this is a pure addition
  - If `oldCount > 0`: this is a modification
  - MVP: treat both as "changed" (same color); optional to distinguish later
- If `newCount == 0` and `oldCount > 0`: this is a pure deletion
  - Add `newStart` to `deletedAnchors` (anchor at the line after the deletion)

For untracked files: detect via `git ls-files --error-unmatch`, and if untracked, return all lines as a single changed range `[1, lineCount]`.

### Data Structures

```
struct GitChangeResult {
    let changedRanges: [ClosedRange<Int>]  // Line ranges (1-indexed)
    let deletedAnchors: [Int]               // Line numbers where deletions occurred
    let isUntracked: Bool                   // True if file is not in git
}
```

### File Changes

**src/Git/GitDiffParser.swift** (create)
- `GitDiffParser` class
- `func parseChanges(forFile fileURL: URL, repoRoot: URL) async throws -> GitChangeResult`
- Run `git diff --unified=0 HEAD -- <relativePath>`
- Parse output and return structured result

**src/Git/DiffHunk.swift** (create)
- `DiffHunk` struct representing a parsed hunk
- Properties: `oldStart`, `oldCount`, `newStart`, `newCount`
- Static parse method: `static func parse(hunkHeader: String) -> DiffHunk?`

**src/Git/GitChangeResult.swift** (create)
- `GitChangeResult` struct as defined above
- Encodable to JSON for passing to JavaScript

### Risks

| Risk | Mitigation |
|------|------------|
| Hunk header parsing edge cases | Handle single-line hunks where count is omitted (e.g., `@@ -5 +5 @@` means count=1) |
| Binary files | Detect "Binary files differ" message and return empty result |
| Renamed files | May not show history; accept this limitation for MVP |
| File with no HEAD (new in staging) | Handle by treating as untracked/all-added |

### Implementation Plan

**Phase 1: Hunk Parsing**
- [x] Create `src/Git/DiffHunk.swift`
- [x] Implement regex or string parsing for `@@ -oldStart,oldCount +newStart,newCount @@`
- [x] Handle edge case: count omitted means count=1 (e.g., `@@ -5 +7,3 @@` means oldCount=1)
- [x] Write unit tests for hunk parsing

**Phase 2: Diff Execution**
- [x] Create `src/Git/GitChangeResult.swift`
- [x] Create `src/Git/GitDiffParser.swift`
- [x] Implement running `git diff --unified=0 HEAD -- <path>`
- [x] Extract relative path from file URL and repo root

**Phase 3: Output Parsing**
- [x] Parse diff output line by line
- [x] Find lines starting with `@@` and parse as hunks
- [x] Convert hunks to changedRanges and deletedAnchors
- [x] Handle empty diff (clean file) -> empty result

**Phase 4: Untracked File Detection**
- [x] Before diffing, run `git ls-files --error-unmatch -- <path>`
- [x] If exit code != 0, file is untracked
- [x] For untracked: count lines in file, return `changedRanges: [1...lineCount]`

**Phase 5: Edge Cases**
- [x] Test with binary files (should return empty or skip)
- [x] Test with file that has no commits yet (new repo)
- [x] Test with file added to index but not committed

---

## Testing

### Automated Tests

Tests go in `Tests/GitDiffParserTests.swift`. Use `GitTestHelper` from repo-detection spec to create test repos.

**DiffHunk parsing tests:**

- [x] `testParseSimpleHunk` - Input: `@@ -10,5 +12,3 @@`, verify oldStart=10, oldCount=5, newStart=12, newCount=3
- [x] `testParseHunkOmittedOldCount` - Input: `@@ -10 +12,3 @@`, verify oldCount=1
- [x] `testParseHunkOmittedNewCount` - Input: `@@ -10,5 +12 @@`, verify newCount=1
- [x] `testParseHunkBothOmitted` - Input: `@@ -10 +12 @@`, verify both counts=1
- [x] `testParseHunkAtStart` - Input: `@@ -0,0 +1,5 @@` (addition at start), verify correctly parsed
- [x] `testParseInvalidHunk` - Input: `not a hunk`, verify returns nil

**Integration tests (require temp git repos):**

- [x] `testAddedLines` - Create repo, commit file, add new lines at end, verify changedRanges includes those lines
- [x] `testModifiedLines` - Create repo, commit file, change a line, verify changedRanges includes that line
- [x] `testDeletedLines` - Create repo, commit file with 10 lines, delete lines 5-7, verify deletedAnchors contains anchor point
- [x] `testMultipleHunks` - Make changes in multiple places, verify all hunks captured
- [x] `testCleanFile` - File with no changes, verify empty changedRanges and deletedAnchors
- [x] `testUntrackedFile` - File not in git, verify isUntracked=true and all lines in changedRanges
- [x] `testMixedAddAndDelete` - Add some lines, delete others, verify both changedRanges and deletedAnchors populated
- [x] `testFileInSubdirectory` - File in `docs/`, verify relative path computed correctly

### Test Fixtures

Create `Tests/Fixtures/diff-samples/` with sample diff outputs for unit testing the parser without git:

- `addition.diff` - Pure line additions
- `deletion.diff` - Pure line deletions
- `modification.diff` - Line modifications
- `multiple-hunks.diff` - Multiple hunks in one file
- `empty.diff` - Clean file (no output)

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| 2026-01-10 | PASS | All 54 tests pass (24 unit + 10 integration for GitDiffParser) |

### Verification

This spec is pure backend logic with no UI. All verification is covered by automated tests above. No manual or MCP verification needed.
