# Print Support

## Meta
- Status: Complete
- Branch: main
- Dependencies: 260110-stage2-webview-renderer.md, 260110-stage5-git-gutter.md

---

## Business

### Problem
Users want to print rendered Markdown documents for documentation, review meetings, or offline reference. Currently there is no print functionality.

### Solution
Add print support (Cmd+P) using `NSPrintOperation` with WKWebView. Print settings (gutter, line numbers, margin) are configured in Preferences > Print. Always use light theme for printing.

### Behaviors
- **Cmd+P:** Opens macOS print dialog directly
- **Gutter setting:** Include/exclude Git change markers in print (Preferences)
- **Line numbers setting:** Include/exclude line numbers in print (Preferences)
- **Margin setting:** Configurable left/right margin in points (Preferences)
- **Theme:** Always light mode for print (dark wastes ink)

### Descoped Features
- **Header/footer:** WKWebView's `NSPrintOperation` does not support custom headers/footers. Attempts to inject HTML elements fail because:
  1. `position: fixed` elements don't repeat on each printed page in WebKit
  2. `NSPrintInfo` header/footer properties are ignored by WKWebView print operations
  3. CSS `@page` margin boxes have limited WebKit support
  This is a fundamental WKWebView limitation with no viable workaround.

---

## Technical

### Approach

WKWebView supports printing via `NSPrintOperation`. Before printing, inject CSS classes to show/hide optional elements (gutter, line numbers) and force light theme. Use `@media print` CSS rules for print-specific styling.

Flow:
1. User presses Cmd+P
2. Swift reads print preferences from PreferencesManager
3. Swift sets CSS classes on WebView body element via JavaScript
4. Swift creates `NSPrintOperation` from WKWebView with configured margins
5. macOS print dialog appears
6. After print completes/cancels, restore original display state (remove CSS classes)

### File Changes

**AppMain/RedMarginApp.swift** (modify)
- Add `Notification.Name.printDocument` extension
- Add File > Print menu item with Cmd+P shortcut
- Post notification to active document window

**AppMain/DocumentView.swift** (modify)
- Listen for `.printDocument` notification
- Add `executePrint()` method that:
  - Reads print settings from PreferencesManager
  - Adds CSS classes via JavaScript (`print-light-theme`, `print-hide-gutter`, `print-hide-line-numbers`)
  - Creates NSPrintInfo with A4 paper and configured margins
  - Runs NSPrintOperation with completion handler to clean up CSS classes

**src/Preferences/PreferencesManager.swift** (modify)
- Add `printMargin: Double` (default: 28 pt)
- Add `printShowGutter: Bool` (default: true)
- Add `printShowLineNumbers: Bool` (default: false)

**src/Preferences/PreferencesView.swift** (modify)
- Add Print tab with:
  - Toggle for gutter markers
  - Toggle for line numbers
  - Slider for margin (18-72 pt)

**WebRenderer/styles/print.css** (create)
- `.print-hide-gutter #gutter-container { display: none; }`
- `.print-hide-line-numbers #line-numbers-container { display: none; }`
- `@media print` rules for page breaks, colors, layout

**WebRenderer/styles/light.css** (modify)
- Add `.print-light-theme` selector alongside `:root` for shared variables
- Ensures print always uses light colors regardless of system theme

**WebRenderer/src/renderer.html** (modify)
- Add `<link rel="stylesheet" href="../styles/print.css">` after other stylesheets

### Risks

| Risk | Mitigation |
|------|------------|
| Print classes not applied before print starts | Use completion handler on JS evaluation before triggering print |
| Gutter positioning breaks in print | Test print layout; may need print-specific gutter CSS adjustments |
| WKWebView print operation is async | Handle completion/cancellation to restore display state |

### Implementation Plan

**Phase 1: Print CSS**
- [x] Create `WebRenderer/styles/print.css` with `@media print` rules
- [x] Add print-hide classes for gutter and line numbers
- [x] Add `.print-light-theme` class to force light colors
- [x] Add page break rules for code blocks and tables
- [x] Link print.css in renderer.html
- [x] Update light.css with `.print-light-theme` selector

**Phase 2: Print Preferences**
- [x] Add print settings to PreferencesManager (margin, gutter, line numbers)
- [x] Add Print tab to PreferencesView with controls

**Phase 3: Print Execution**
- [x] Add `.printDocument` notification to RedMarginApp.swift
- [x] Add File > Print menu item with Cmd+P
- [x] Implement `executePrint()` in DocumentView
- [x] Apply CSS classes based on preferences before print
- [x] Configure NSPrintInfo with A4 paper and margins from preferences
- [x] Clean up CSS classes after print completes

---

## Testing

### Manual Verification

- [x] Cmd+P opens macOS print dialog
- [x] Preview shows light theme regardless of app theme
- [x] Gutter hidden when preference off
- [x] Line numbers hidden when preference off (default)
- [x] Margin setting affects print output
- [x] Code blocks don't break across pages
- [x] Print to PDF produces clean output
