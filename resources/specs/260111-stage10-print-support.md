# Print Support

## Meta
- Status: Draft
- Branch: feature/print-support
- Dependencies: 260110-stage2-webview-renderer.md, 260110-stage5-git-gutter.md

---

## Business

### Problem
Users want to print rendered Markdown documents for documentation, review meetings, or offline reference. Currently there is no print functionality.

### Solution
Add print support (Cmd+P) using `NSPrintOperation` with WKWebView. Provide a configuration sheet with toggles for gutter markers, line numbers, and header/footer. Always use light theme for printing.

### Behaviors
- **Cmd+P:** Opens print configuration sheet
- **Print button:** Triggers macOS print dialog with configured options
- **Cancel button:** Dismisses sheet without printing
- **Gutter toggle:** Include/exclude Git change markers in print
- **Line numbers toggle:** Include/exclude line numbers in print
- **Header/footer toggle:** Include/exclude file path, date, page numbers
- **Theme:** Always light mode for print (dark wastes ink)

---

## Technical

### Approach

WKWebView supports printing via `NSPrintOperation`. Before printing, inject CSS classes to show/hide optional elements (gutter, line numbers) and force light theme. Use `@media print` CSS rules for print-specific styling.

Flow:
1. User presses Cmd+P
2. Print configuration sheet appears with toggles
3. User clicks Print
4. Swift sets CSS classes on WebView body element via JavaScript
5. Swift creates `NSPrintOperation` from WKWebView
6. macOS print dialog appears
7. After print completes/cancels, restore original display state

Header/footer uses `NSPrintInfo` properties (`headerAndFooter`) with custom view or print info dictionary for file path, date, and page numbers.

### File Changes

**AppMain/RedMarginApp.swift** (modify)
- Add `Notification.Name.printDocument` extension
- Add File > Print menu item with Cmd+P shortcut
- Post notification to active document window

**AppMain/DocumentView.swift** (modify)
- Add `@State var showPrintSheet: Bool`
- Add `@State var printConfig: PrintConfiguration`
- Listen for `.printDocument` notification
- Present `PrintConfigSheet` when triggered
- Add `executePrint()` method that configures WebView and triggers print

**src/Views/PrintConfigSheet.swift** (create)
- SwiftUI sheet with three toggles:
  - `includeGutter: Bool` (default: true)
  - `includeLineNumbers: Bool` (default: false)
  - `includeHeaderFooter: Bool` (default: true)
- Print and Cancel buttons
- Binding to `PrintConfiguration` struct
- `onPrint` callback

**src/Models/PrintConfiguration.swift** (create)
- `struct PrintConfiguration` with toggle properties
- Default values for each option

**src/Views/MarkdownWebView.swift** (modify)
- Add `static func preparePrint(webView:config:)` method
  - Calls JavaScript to add print classes to body
  - Sets `print-hide-gutter`, `print-hide-line-numbers`, `print-light-theme` classes
- Add `static func restoreFromPrint(webView:)` method
  - Removes print classes after printing

**src/Printing/PrintManager.swift** (create)
- `class PrintManager`
- `static func print(webView:fileURL:config:)` method
- Creates `NSPrintInfo` with header/footer settings
- Creates `NSPrintOperation` from webView
- Configures header: file path (left), date (right)
- Configures footer: page number (center)
- Runs print operation

**WebRenderer/styles/print.css** (create)
- `@media print` rules
- `.print-hide-gutter #git-gutter { display: none; }`
- `.print-hide-gutter #gutter-container { width: 0; }`
- `.print-hide-line-numbers #line-numbers-container { display: none; }`
- `.print-light-theme` forces light theme colors
- Page break rules (avoid breaks inside code blocks, tables)
- Hide find bar in print

**WebRenderer/styles/light.css** (modify)
- Add `.print-light-theme` selector alongside `:root` for shared variables
- Ensures print always uses light colors regardless of system theme

**WebRenderer/src/renderer.html** (modify)
- Add `<link rel="stylesheet" href="../styles/print.css">` after other stylesheets

### Risks

| Risk | Mitigation |
|------|------------|
| Print classes not applied before print starts | Use completion handler on JS evaluation before triggering print |
| Header/footer styling limited by NSPrintInfo | Test NSPrintInfo capabilities; fall back to simpler format if needed |
| Gutter positioning breaks in print | Test print layout; may need print-specific gutter CSS adjustments |
| WKWebView print operation is async | Handle completion/cancellation to restore display state |

### Implementation Plan

**Phase 1: Print CSS**
- [ ] Create `WebRenderer/styles/print.css` with `@media print` rules
- [ ] Add print-hide classes for gutter and line numbers
- [ ] Add `.print-light-theme` class to force light colors
- [ ] Add page break rules for code blocks and tables
- [ ] Link print.css in renderer.html
- [ ] Update light.css with `.print-light-theme` selector

**Phase 2: Print Configuration UI**
- [ ] Create `src/Models/PrintConfiguration.swift` struct
- [ ] Create `src/Views/PrintConfigSheet.swift` SwiftUI view
- [ ] Add toggles for gutter, line numbers, header/footer
- [ ] Add Print and Cancel buttons
- [ ] Style to match system appearance

**Phase 3: WebView Print Preparation**
- [ ] Add `preparePrint(webView:config:)` to MarkdownWebView
- [ ] Add `restoreFromPrint(webView:)` to MarkdownWebView
- [ ] Implement JavaScript class toggling for print options

**Phase 4: Print Manager**
- [ ] Create `src/Printing/PrintManager.swift`
- [ ] Implement `NSPrintOperation` creation from WKWebView
- [ ] Configure `NSPrintInfo` for header/footer
- [ ] Handle print completion callback

**Phase 5: Integration**
- [ ] Add `.printDocument` notification to RedMarginApp.swift
- [ ] Add File > Print menu item with Cmd+P
- [ ] Add print sheet state to DocumentView
- [ ] Wire notification to show print sheet
- [ ] Implement `executePrint()` in DocumentView
- [ ] Test full print flow

---

## Testing

### Automated Tests

Tests in `Tests/PrintTests.swift`:

- [ ] `testPrintConfigurationDefaults` - Verify default config has gutter=true, lineNumbers=false, headerFooter=true
- [ ] `testPreparePrintAddsClasses` - Call preparePrint with config, verify body has expected classes via JS query
- [ ] `testRestoreFromPrintRemovesClasses` - Call restore, verify print classes removed
- [ ] `testPrintManagerCreatesOperation` - Verify PrintManager returns valid NSPrintOperation

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### Manual Verification

After implementation, manually verify:

- [ ] Cmd+P opens print configuration sheet
- [ ] Toggle switches work and update state
- [ ] Cancel dismisses sheet without printing
- [ ] Print button opens macOS print dialog
- [ ] Preview shows light theme regardless of app theme
- [ ] Gutter hidden when toggle off
- [ ] Line numbers hidden when toggle off
- [ ] Header shows file path and date
- [ ] Footer shows page numbers
- [ ] Code blocks don't break across pages
- [ ] Tables don't break mid-row
- [ ] Print to PDF produces clean output
