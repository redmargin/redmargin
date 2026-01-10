# PROJECT.md

Project-specific instructions for AI agents working on RedMargin.

---

## Project Overview

RedMargin is a native macOS Markdown viewer with Git gutter indicators in the rendered view - think VS Code's change gutter, but for beautifully rendered Markdown.

**Tech stack:** Swift 5.9+, SwiftUI (with AppKit interop), WKWebView, markdown-it (JS), macOS 14.0+

---

## Specifications

Specs live in `resources/specs/` with date prefix format `yymmdd-description.md`.

**When implementing a spec:** Update checkboxes after EVERY completed step.

---

## Code Style

### Swift

- Use Swift 5.9+ features (macros, `@Observable`, etc.)
- Prefer `async/await` over completion handlers
- Use `@MainActor` for all UI code
- No force unwrapping (`!`) except for IBOutlets and known-safe cases
- Prefer guard-let over nested if-let

### JavaScript (embedded in WKWebView)

- ES6+ syntax
- No external dependencies beyond markdown-it and its plugins
- All JS bundled into the app

### Naming

- Types: `PascalCase`
- Functions/variables: `camelCase`
- Constants: `camelCase` (not `SCREAMING_SNAKE`)
- Files match their primary type: `GitChangeProvider.swift`

### Project Structure

```
.
├── src/                    # Swift source code
│   ├── App/                # App entry, delegate, menus
│   ├── Windows/            # Window management
│   ├── Views/              # SwiftUI views and WebView wrapper
│   ├── Git/                # Git integration (diff parsing, repo detection)
│   ├── FileWatching/       # FSEvents, file/git change monitoring
│   ├── Preferences/        # Settings UI and storage
│   └── Utilities/          # Helpers, extensions
├── WebRenderer/            # JS/CSS for WKWebView
│   ├── src/                # JS source (markdown-it, gutter logic)
│   └── styles/             # CSS themes (light/dark)
├── Tests/                  # Swift test files
│   └── Fixtures/           # Test repos and sample files
├── resources/
│   ├── specs/              # Feature specifications
│   ├── docs/
│   │   ├── CHANGELOG.md
│   │   └── scratch.md
│   └── scripts/            # Build scripts, utilities
├── build/                  # Build output (app bundle)
└── README.md               # Project readme
```

---

## Building

**ALWAYS use the build script:** `resources/scripts/build.sh`

This script:
- Builds with `swift build`
- Bundles WebRenderer assets into the app
- Updates the executable in the existing app bundle
- Preserves the app bundle identity (no permission prompts)

**NEVER** recreate the app bundle from scratch - this resets macOS permissions.

**Do not launch the app.** Marco will do that himself.

---

## Linting

Run `swiftlint lint --quiet` before building and committing. Config is in `.swiftlint.yml`.

---

## Testing

- Test files go in `Tests/`
- Test fixtures (sample repos, Markdown files) go in `Tests/Fixtures/`
- No mocks - prefer real file system operations with temp directories
- Always build and run the app to verify changes work

**NEVER run the full test suite.** Always run tests one file at a time:
```bash
xcodebuild test -scheme RedMargin -destination 'platform=macOS' -only-testing:RedMarginTests/SomeTestClass
```

**NEVER use "pre-existing" as an excuse.** If a test fails, fix it.

---

## MCP UI Verification

Use `macos-ui-automation` MCP for UI verification. **Critical rules:**

1. **App does not need to be frontmost.** MCP uses accessibility APIs and can interact with background apps. Marco needs to work while you test.
2. **Never use osascript that requires the app to be active.** If you must use osascript, ensure it works with background apps.
3. **Prefer MCP tools over osascript.** Use `find_elements_in_app`, `click_element_by_selector`, `type_text_to_element_by_selector`.
4. **Open files via command line:** `open -a RedMargin file.md` (doesn't steal focus)
5. **Quit app via command line:** `osascript -e 'quit app "RedMargin"'` (works in background)

Example workflow:
```bash
# Open a file (doesn't steal focus)
open -a RedMargin /path/to/test.md

# Verify via MCP (works while Marco works)
# find_elements_in_app("RedMargin", "$..[?(@.role=='window')]")

# Quit when done
osascript -e 'quit app "RedMargin"'
```

---

## Git

- Branch naming: `feature/git-gutter`, `fix/sourcepos-parsing`
- Commit messages: imperative mood, concise ("Add gutter overlay", not "Added gutter overlay")
- Never commit `.xcuserdata/` or other Xcode user state

---

## Documentation

- Docs live in `resources/docs/`
- Use /update-docs skill to update documentation (don't manually edit CHANGELOG.md)

---

## Dates

Before creating date-stamped files or doing web searches, run `date` to check today's actual date.

---

## Implementation Workflow

**Always add to spec first.** Before implementing any feature or fix:
1. Create or update a spec in `resources/specs/`
2. Get approval if it's a new spec
3. Then implement, updating checkboxes as you go

**Always add automated tests.** Every feature or fix should have corresponding tests in `Tests/`.

---

## Key Technical Notes

### Swift ↔ JS Bridge

- Use `WKUserScript` to inject the renderer bundle
- Call JS via `evaluateJavaScript`: `window.App.render({ markdown, changedRanges, deletedAnchors, options })`
- Options: theme, allowRemoteImages, basePath

### Git Integration

- Use system `git` via `Process` (shell-out)
- Parse `git diff --unified=0` output for change ranges
- Detect repo root via `git rev-parse --show-toplevel`

### Gutter Alignment

- markdown-it emits `data-sourcepos` on block elements
- JS maps source lines to rendered DOM positions
- Gutter updates on scroll without re-rendering Markdown

---

## When You Get Stuck

If you've tried 2-3 approaches and something still doesn't work, **stop hacking and research**:

1. Search online for the specific issue
2. Check Apple developer documentation
3. Look for user reports, Stack Overflow, Reddit discussions
4. Present findings and options to Marco

---

## What NOT to Do

- Don't add features not in the current spec
- Don't refactor code that works unless asked
- Don't add comments to obvious code
- Don't create abstractions for single-use code
- Don't hardcode paths - use `~`, `FileManager.default.homeDirectoryForCurrentUser`, etc.

---

## Questions?

If something is unclear in a spec, ask before implementing. Don't guess.
