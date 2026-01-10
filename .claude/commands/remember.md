---
description: Refresh context about this project. Use at the start of sessions or when confused about project conventions.
---

# Remember - Redmargin Project Context

## First: Read the Instructions

1. **User instructions**: `~/.claude/CLAUDE.md` - Marco's global preferences
2. **Project instructions**: `.claude/CLAUDE.local.md` - Redmargin-specific rules

## Build

```bash
resources/scripts/build.sh
```

Never run `swift build` directly. The script builds, creates the app bundle, and installs to /Applications.

## Lint

```bash
swiftlint lint --quiet
```

Run before building and committing.

## Test

JavaScript tests for WebRenderer:

```bash
cd WebRenderer && npm test
```

Swift tests (target specific):

```bash
xcodebuild test -scheme Redmargin -destination 'platform=macOS' -only-testing:RedmarginTests/SomeTestClass
```

## Key Locations

- **Source**: `src/` (App, Views)
- **WebRenderer**: `WebRenderer/` (JS markdown rendering, CSS themes)
- **Tests**: `Tests/` (Swift), `WebRenderer/tests/` (JS)
- **Specs**: `resources/specs/` (date-prefixed: `yymmdd-description.md`)
- **Docs**: `resources/docs/`
- **Build output**: Installs to `/Applications/Redmargin.app`

## Architecture

- SwiftUI app with WKWebView for rendering
- markdown-it (JS) with sourcepos plugin for line mapping
- Light/dark CSS themes following system appearance
- Per-document state (line numbers, scroll position) in UserDefaults

## Quick Reminders

- The year is 2026
- App name is **Redmargin** (not RedMargin)
- Swift 5.9+, SwiftUI, macOS 14.0+
- Don't launch the app after building - Marco will do that
- Don't commit without explicit approval
- When stuck after 2-3 attempts, stop and research
