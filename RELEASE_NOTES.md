Initial public release of Redmargin, a Markdown viewer for macOS with Git diff gutter.

## Features

- **Git gutter** - See which lines changed, were added, or deleted compared to HEAD, right in the rendered view
- **Live Markdown rendering** - GitHub Flavored Markdown with tables, task lists, code blocks, and syntax highlighting
- **Interactive checkboxes** - Click task list items to toggle them; changes save immediately
- **Find in page** - Search with match count and navigation (Cmd+F)
- **Print support** - Print rendered documents with configurable options (Cmd+P)
- **Themes** - Light, dark, or follow system appearance
- **Line numbers** - Optional source line numbers aligned with rendered content
- **Per-document state** - Remembers scroll position and settings for each file

## Requirements

- macOS 14.0+ (Sonoma)

## Security

Redmargin sanitizes HTML in Markdown files to prevent XSS attacks. Remote resources are blocked by default.
