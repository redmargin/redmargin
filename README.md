# Redmargin

A native macOS Markdown viewer with Git gutter indicators in the rendered view.

## What It Does

Redmargin renders Markdown beautifully while showing Git change markers (added/modified/deleted lines) in a left gutter - like VS Code or Zed, but for rendered Markdown instead of source code.

## Features (MVP)

- Rendered Markdown with GFM support (tables, task lists, code blocks)
- Git gutter showing working tree changes vs HEAD
- Find-in-page (Cmd+F) with navigation
- Native text selection and copy
- Auto-refresh on file and Git changes
- Light/dark theme support

## Requirements

- macOS 14.0+
- Swift 5.9+

## Building

```bash
./resources/scripts/build.sh
```

## License

TBD
