# Export to PDF

## Meta
- Status: In Progress
- Branch: main
- Dependencies: 260111-stage10-print-support.md

---

## Business

### Problem
Users want to quickly export rendered Markdown to PDF without going through the print dialog. They want the PDF saved directly to Downloads with the current theme preserved.

### Solution
Add "Export as PDF" (Cmd+E) that exports directly to Downloads folder without showing a print dialog. Uses the current document theme (light or dark) and generates unique filenames if the file already exists.

### Behaviors
- **Cmd+E:** Exports PDF directly to Downloads folder
- **Theme:** Uses current effective theme (light/dark based on system or preference)
- **Filename:** Uses document name with `.pdf` extension
- **Uniqueness:** Appends `-1`, `-2`, etc. if filename exists
- **Feedback:** Shows notification on success, alert on error
- **Works for:** Both local and remote documents

### Out of Scope
- Save dialog for custom location (future enhancement)
- Page range selection
- Custom paper size

---

## Technical

### Approach

Use `WKWebView.createPDF(configuration:)` (macOS 11+) to generate PDF data, then write to Downloads directory. Before creating PDF, apply print CSS classes to ensure proper styling, then restore after.

Flow:
1. User presses Cmd+E
2. Menu item posts `.exportToPDF` notification
3. Active DocumentView/RemoteDocumentView handles notification
4. Add print CSS classes for theme and layout
5. Call `PDFExporter.export()` with webView and filename
6. Generate unique filename in Downloads
7. Create PDF using `WKWebView.createPDF(configuration:)`
8. Write PDF data to file
9. Remove print CSS classes
10. Show success notification or error alert

### File Changes

**src/Printing/PDFExporter.swift** (create)
- `PDFExporter` class with static `export()` method
- Uses `WKPDFConfiguration` with A4 paper size
- Saves to Downloads directory
- Handles unique filename generation

**AppMain/MainMenu.swift** (modify)
- Add "Export as PDF" menu item after "Print..."
- Keyboard shortcut: Cmd+E
- Posts `.exportToPDF` notification

**AppMain/AppDelegate.swift** (modify)
- Add `@objc func exportDocument(_:)` handler

**AppMain/AppDelegateExtensions.swift** (modify)
- Add `.exportToPDF` notification name

**AppMain/DocumentView.swift** (modify)
- Listen for `.exportToPDF` notification
- Add `executeExport()` method
- Show success/error feedback

**AppMain/RemoteDocumentView.swift** (modify)
- Listen for `.exportToPDF` notification
- Add `executeExport()` method
- Show success/error feedback

**Tests/PDFExportTests.swift** (create)
- Test filename generation (uniqueness)
- Test PDF configuration defaults

### Implementation Plan

**Phase 1: Core Exporter**
- [x] Create `src/Printing/PDFExporter.swift` with export logic
- [x] Implement unique filename generation
- [x] Configure WKPDFConfiguration with A4 size

**Phase 2: Menu Integration**
- [x] Add `.exportToPDF` notification name
- [x] Add @objc handler in AppDelegate
- [x] Add "Export as PDF" menu item with Cmd+E

**Phase 3: View Integration**
- [x] Add export handling in DocumentView
- [x] Add export handling in RemoteDocumentView
- [x] Add success notification / error alert

**Phase 4: Testing**
- [x] Create PDFExportTests.swift
- [x] Test filename generation
- [ ] Manual verification

---

## Testing

### Unit Tests
- [ ] Unique filename generation with existing files
- [ ] PDF configuration has correct paper size

### Manual Verification
- [ ] Cmd+E exports local document to Downloads
- [ ] Dark theme preserved in exported PDF
- [ ] Light theme preserved in exported PDF
- [ ] Export same file twice creates unique names
- [ ] Remote document export works
- [ ] Error handling when Downloads not writable
