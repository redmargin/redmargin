# Redmargin

A native macOS Markdown viewer with live rendering.

> **Note:** This is a personal project I built for my own use. I'm sharing it because good macOS Markdown viewers are rare. I'm not actively seeking contributions and may be slow to respond to issues. Feel free to fork if you want to take it in a different direction.

## Features

- **Live Markdown rendering** - View Markdown files as beautifully formatted HTML
- **Interactive checkboxes** - Click to toggle task list items, saves immediately
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
| Toggle Line Numbers | Cmd-L |

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

Stage 4 complete - Git diff parsing for detecting changed/added/deleted lines. See `resources/specs/` for design documents.

## License

MIT License - see [LICENSE](LICENSE) for details.
