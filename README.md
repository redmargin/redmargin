# Redmargin

Markdown viewer with Git change indicators, syntax highlighting, file sidebar, remote file access over SSH, and PDF export.

> I built this for myself after trying various Markdown viewers and not finding one that fit how I work. Putting it out there in case it clicks for someone else too. Happy to hear feedback or accept contributions, though responses may be slow. Fork away if you'd like to take it somewhere new.

## Features

- **Git change indicators** — Gutter shows added/modified/deleted lines compared to HEAD. Updates on commit or branch switch.
- **Syntax highlighting** — Code blocks render with language-aware coloring. Supports Python, JavaScript, Swift, Rust, Go, and more.
- **File sidebar** — Browse Markdown files in your repo (Cmd+1). Collapsible folders, current file highlighted.
- **Remote file access over SSH** — Open Markdown on remote servers (Cmd+Shift+O). Git gutter, checkboxes, and sidebar all work remotely.
- **PDF export** — Export with theme, gutter, and line numbers preserved (Cmd+E). Saves to Downloads.
- **Find in page** — Search with match count and navigation (Cmd+F)
- **Interactive checkboxes** — Click to toggle, saves immediately (local and remote)
- **Print support** — Configurable gutter and line number visibility (Cmd+P)
- **Per-document settings** — Each file remembers view preferences, scroll position, window size
- **Light/dark themes** — Follows system appearance
- **Line numbers** — Optional, aligned with rendered content
- **Local images** — Relative paths work correctly

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
| Open Remote | Cmd-Shift-O |
| Export PDF | Cmd-E |
| Print | Cmd-P |
| Preferences | Cmd-, |
| Refresh | Cmd-R |
| Toggle Sidebar | Cmd-1 |
| Toggle Line Numbers | Cmd-L |
| Toggle Gutter | Cmd-Option-G |
| Toggle Git Indicators | Cmd-Shift-I |
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
│   ├── Core/             # Core functionality
│   │   ├── Git/          # Git operations, diff parsing
│   │   ├── Remote/       # SSH client, RPC protocol
│   │   └── FileProvider/ # Local/remote file abstraction
│   └── Preferences/      # Settings management
├── Server/               # Remote daemon (deployed to SSH hosts)
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

v1.0.0 - See `resources/docs/CHANGELOG.md` for version history.

## License

MIT License - see [LICENSE](LICENSE) for details.
