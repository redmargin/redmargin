# Redmargin

Markdown viewer for macOS with Git change indicators, remote file access over SSH, Mermaid diagrams, syntax highlighting, and PDF export.

## Features

- **Git change indicators** — Gutter shows added, modified, and deleted lines compared to HEAD. Sidebar file rows show modified, staged, untracked, and conflict status.
- **Remote file access** — Open Markdown on remote servers via SSH (Cmd+Shift+O). Git gutter, checkboxes, and sidebar all work remotely.
- **File sidebar** — Browse Markdown files in the repository or directory (Cmd+1). Collapsible folders, current file highlighted, and git status bars enabled by default.
- **Syntax highlighting** — Code blocks render with language-aware coloring. Supports Python, JavaScript, Swift, Rust, Go, and more.
- **Mermaid diagrams** — Fenced `mermaid` blocks render as diagrams, follow the active theme, and print/export with the preview.
- **Interactive checkboxes** — Click to toggle, saves immediately (local and remote).
- **Find in page** — Search with match count and navigation (Cmd+F).
- **PDF export** — Export with theme, gutter, line numbers, margins, and font size preserved (Cmd+E). Saves to Downloads.
- **Print support** — Configurable gutter, line number visibility, margins, and font size (Cmd+P).
- **Light/dark themes** — System, light, or dark (set in Preferences).
- **Per-document settings** — Each file remembers view preferences, scroll position, and window size.
- **Line numbers** — Optional display aligned with rendered content.

## Security

Markdown files can contain inline HTML which creates XSS risks. Redmargin applies multiple layers of protection:

- **HTML sanitization** — Allowlist-based sanitizer strips scripts, event handlers, and dangerous tags.
- **URL scheme allowlist** — Only http/https/mailto allowed in links; file:// and other schemes blocked.
- **Navigation policy** — External links open in system browser; file:// navigation blocked.
- **Remote loading blocked** — External resources blocked by default via WKContentRuleList (images configurable in Preferences).
- **Safe data URIs only** — Only raster image formats (PNG, JPEG, GIF, WebP) allowed; SVG blocked (can contain scripts).
- **Mermaid SVG sanitization** — Rendered Mermaid output is sanitized before insertion, and invalid diagrams fall back to source text with an error banner.
- **Local images** — Loadable from any path readable by the user, not restricted to document directory.

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode Command Line Tools

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

1. Rebuild the Linux remote server binary on `devtest` when server or core sources are newer
2. Compile with Swift Package Manager
3. Create the app bundle with WebRenderer assets and server binaries
4. Install to /Applications

## Keyboard Shortcuts

| Action | Shortcut |
| ------ | -------- |
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
│   ├── src/              # markdown-it, sourcepos, sanitizer, Mermaid
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

v1.0.2 - See `resources/docs/CHANGELOG.md` for version history.

## License

MIT License - see [LICENSE](LICENSE) for details.
