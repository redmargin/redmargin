# Redmargin Project Instructions

macOS Markdown viewer with Git gutter indicators, folder workspaces, remote SSH support, Mermaid diagrams, and PDF export. Swift 5.9+, SwiftUI, WKWebView, markdown-it, macOS 14.0+

---

## User Intent

- If Marco asks a question, answer the question only. Do not implement, edit files, run builds/tests, or otherwise change the repo unless Marco explicitly asks for changes.

---

## Building

For local build verification, run `./resources/scripts/build.sh`. Never run `swift build`, `xcodebuild`, `swiftlint`, or substitute verification commands unless Marco explicitly asks.

---

## Linting

For commits, use the repository/agent commit workflow. Do not run standalone `swiftlint` unless Marco explicitly asks.

---

## Testing

- Test files in `Tests/`, fixtures in `Tests/Fixtures/`
- No mocks - use real file system with temp directories
- For local verification, use `./resources/scripts/build.sh` unless Marco explicitly asks for a specific test command
- Never pipe output through `head`/`tail` - show full output
- Never suggest browser cache as solution

---

## Debugging

- NEVER ask Marco to check Console.app - figure it out yourself
- Use `log show` command to read system logs programmatically
- Add debug logging, rebuild, reproduce, read logs via CLI

---

## MCP Usage

### Subagent Pattern

Use judgment on when to use a subagent for MCP calls:

**Direct call** - Small/quick MCP calls where output is manageable

**Subagent pattern** - Large outputs (docs, database queries, API responses):

1. Spawn subagent to make the MCP call
2. Subagent writes structured/summarized output to `.mcp/<server>/<tool>-<description>.md`
3. Subagent greps and returns only what main agent needs
4. Main agent never sees full MCP output

**Caching rules:**

- Check `.mcp/` before making new calls
- Cache persists until explicitly told to invalidate
- Never re-run if cached data answers the question

### UI Verification

Use `macos-ui-automation` MCP. **App does not need to be frontmost** - MCP uses accessibility APIs.

```bash
# Open file (doesn't steal focus)
open -a Redmargin /path/to/file.md

# Verify via MCP
# find_elements_in_app("Redmargin", "$..[?(@.role=='window')]")

# Quit when done
osascript -e 'quit app "Redmargin"'
```

Prefer MCP tools over osascript. Never use osascript requiring active app.

---

## Browser Testing

- Set 1500px viewport first
- Hydration waits (500ms after navigation) OK for Svelte 5
- Use querySelector for complex interactions
- IDs when available, selectors when needed

---

## Git

Remotes:

- `origin` = MAF27/redmargin (private) - regular pushes go here
- `public` = redmargin/redmargin (public) - only push for releases

Branch naming: `feature/git-gutter`, `fix/sourcepos-parsing`

---

## Key Technical Notes

### Swift ↔ JS Bridge

- `WKUserScript` injects renderer bundle
- Call JS via `evaluateJavaScript`: `window.App.render({ markdown, changedRanges, deletedAnchors, options })`
- Options: theme, allowRemoteImages, basePath

### Git Integration

- Shell out to system `git` via `Process`
- Parse `git diff --unified=0` for change ranges
- Parse `git status --porcelain -uall` for sidebar file status indicators
- Detect repo root via `git rev-parse --show-toplevel`

### Gutter Alignment

- markdown-it emits `data-sourcepos` on block elements
- JS maps source lines to rendered DOM positions
- Gutter updates on scroll without re-rendering

---

## Specs & Docs

- Specs: `resources/specs/`
- Docs: `resources/docs/`
- Add or update a spec for broad, multi-phase, or ambiguous work. Small scoped changes can be implemented directly when the behavior is clear.
- Always add automated tests for features/fixes

## Migrations

- Forward migrations never delete data
- Must be idempotent (can run repeatedly)
- Use migrations table to track applied
- Get explicit approval before running

---

## Remote Development Server

The `devtest` SSH alias points to a Linux (Ubuntu 22.04) development server used for:

- Building Linux server binaries (`resources/scripts/build-linux.sh`)
- Running Linux-specific tests
- Integration testing SSH remote file features

Commands:

- Build Linux binary: `./resources/scripts/build-linux.sh`
- Run Linux-specific tests on devtest only when explicitly requested, with a timeout guard

**IMPORTANT:** Always run remote/SSH tests with timeouts - they tend to hang:

```bash
swift test --filter RemoteIntegrationTests 2>&1 & pid=$!; sleep 60; kill $pid 2>/dev/null
# Or use timeout command:
timeout 60 swift test --filter SSHConnectionTests
```
