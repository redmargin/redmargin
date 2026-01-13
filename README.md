# Redmargin

Markdown viewer for macOS with Git diff gutter.

> **Note:** This is a personal project I built because I couldn't find a Markdown viewer that fit my needs. I'm not actively seeking contributions and may be slow to respond to issues. Feel free to fork if you want to take it in a different direction.

## Features

- **Git gutter** - Shows changed/added/deleted lines compared to HEAD
- **Live Markdown rendering** - View Markdown files as beautifully formatted HTML
- **Find in page** - Search text with match count and navigation (Cmd+F)
- **Interactive checkboxes** - Click to toggle task list items, saves immediately
- **Preferences** - Theme (light/dark/system), inline code colors, gutter visibility, remote images
- **Print support** - Print rendered documents (Cmd+P) with configurable gutter/line number visibility
- **Light/dark themes** - Follows system appearance automatically
- **Line numbers** - Optional source line numbers aligned with rendered content
- **Local images** - Relative image paths work correctly
- **Per-document state** - Remembers scroll position and line number visibility per file
- **Native macOS** - SwiftUI shell with WKWebView rendering

## Security

Markdown files can contain inline HTML which creates XSS risks. Redmargin applies multiple layers of protection:

- **HTML sanitization** - Allowlist-based sanitizer strips scripts, event handlers, and dangerous tags
- **URL scheme allowlist** - Only http/https/mailto allowed in links; file:// and other schemes blocked
- **Navigation policy** - External links open in system browser; file:// navigation blocked
- **Remote loading blocked** - External resources blocked by default via WKContentRuleList (images configurable in Preferences)
- **Safe data URIs only** - Only raster image formats (PNG, JPEG, GIF, WebP) allowed; SVG blocked (can contain scripts)
- **Local images** - Images can be loaded from any path readable by the user (not restricted to document directory)

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 5.9+ (Xcode Command Line Tools)

## Building

```bash
# Clone the repository
git clone https://github.com/redmargin/redmargin.git
cd redmargin

# Build and install to /Applications
./resources/scripts/build.sh

# Run
open /Applications/Redmargin.app
```

The build script will:
1. Compile with Swift Package Manager
2. Create the app bundle with WebRenderer assets
3. Install to /Applications

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open File | Cmd-O |
| Preferences | Cmd-, |
| Print | Cmd-P |
| Refresh | Cmd-R |
| Toggle Line Numbers | Cmd-L |
| Find | Cmd-F |
| Find Next | Cmd-G |
| Find Previous | Cmd-Shift-G |

## Project Structure

```
redmargin/
├── AppMain/              # App entry point, window management
├── src/                  # Swift library source
│   ├── App/              # Document management, security
│   ├── Views/            # SwiftUI views, WebView wrapper
│   ├── Git/              # Git operations, diff parsing
│   └── Preferences/      # Settings management
├── WebRenderer/          # JavaScript markdown rendering
│   ├── src/              # markdown-it, sourcepos, sanitizer
│   ├── styles/           # Light/dark CSS themes
│   └── tests/            # JavaScript tests
├── Tests/                # Swift XCTest suite
├── resources/
│   ├── specs/            # Feature specifications
│   ├── scripts/          # Build scripts
│   └── icons/            # App icon assets
└── Package.swift
```

## Status

v0.42.0 - Feature complete. See `resources/docs/CHANGELOG.md` for version history.

## License

MIT License - see [LICENSE](LICENSE) for details.
