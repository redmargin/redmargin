# Redmargin

A native macOS Markdown viewer with live rendering.

> **Note:** This is a personal project I built for my own use. I'm sharing it because good macOS Markdown viewers are rare. I'm not actively seeking contributions and may be slow to respond to issues. Feel free to fork if you want to take it in a different direction.

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
├── src/                  # Swift source
│   ├── App/              # Entry point, document management
│   └── Views/            # SwiftUI views, WebView wrapper
├── WebRenderer/          # JavaScript markdown rendering
│   ├── src/              # markdown-it, sourcepos plugin
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

Stage 10 in progress - Print support with Cmd+P, configuration sheet for gutter/line number visibility. See `resources/specs/` for design documents.

## License

MIT License - see [LICENSE](LICENSE) for details.
