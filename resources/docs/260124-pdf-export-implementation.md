# PDF Export Implementation

Technical documentation for the Export to PDF feature (Cmd+E).

## Overview

PDF export uses NSPrintOperation with post-processing for dark theme support. WebKit has fundamental limitations that prevent CSS-only solutions for dark backgrounds in print.

## WebKit Limitations

These are long-standing WebKit bugs that will likely never be fixed:

- **Bug #6790 (2006)**: `position: fixed` elements don't repeat on subsequent printed pages
- **Bug #17205 (2008)**: Table headers/footers don't repeat in Safari print
- **Bug #15548 (2007)**: `@page { background }` not implemented
- Safari ignores `@page { margin: 0 }` - has hardcoded margins
- `-webkit-print-color-adjust: exact` doesn't work on body element for margins

## Failed Approaches

### 1. `WKWebView.createPDF(configuration:)`

The WebKit API for creating PDFs captures a screenshot-like render. It doesn't use print pagination, so multi-page documents get cut off at arbitrary points rather than breaking at logical page boundaries.

### 2. Zero margins + CSS padding

```swift
printInfo.topMargin = 0
printInfo.bottomMargin = 0
```

Combined with CSS body padding for margins. Problem: CSS padding only creates margins on page 1. Pages 2+ have content against the edge.

### 3. Position-fixed background div

```javascript
var bg = document.createElement('div');
bg.style.cssText = 'position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: #1a1a1a;';
document.body.insertBefore(bg, document.body.firstChild);
```

Due to WebKit Bug #6790, position:fixed elements only appear on page 1 when printing. Result: dark background on page 1, white on pages 2+.

### 4. CSS @page rules

```css
@page { margin: 0; background: #1a1a1a; }
```

Safari completely ignores @page background. It also ignores @page margin in favor of its own hardcoded values.

## Working Solution

### Architecture

1. **NSPrintOperation** with `jobDisposition = .save` for proper print infrastructure
2. **NSPrintInfo margins** set to desired values (56pt top/bottom, 28pt left/right)
3. **Post-processing** with PDFKit/CoreGraphics for dark theme

### Why Post-Processing Works

WebKit creates the PDF with white margins (unavoidable). Post-processing opens the PDF and for each page:

1. Creates a new PDF context
2. Draws a solid background color filling the entire page bounds
3. Draws the original page content on top

This paints the dark background behind the content at the PDF level, bypassing WebKit's CSS limitations entirely.

### Code Flow

```
PDFExporter.export()
    ├── Inject CSS classes for theme
    ├── Set document background color via JavaScript
    ├── Configure NSPrintInfo with margins
    ├── Run NSPrintOperation (creates PDF with white margins)
    └── PDFExportCompletionHandler.printOperationDidRun()
            ├── Cleanup CSS classes
            └── If dark theme: applyBackground()
                    ├── Open PDF with PDFDocument
                    ├── For each page:
                    │   ├── Begin new page in CGContext
                    │   ├── Fill page bounds with dark color
                    │   └── Draw original page content on top
                    └── Write new PDF back to file
```

### Key Implementation Details

**NSPrintInfo configuration:**
```swift
printInfo.paperSize = NSSize(width: 595.28, height: 841.89)  // A4
printInfo.topMargin = 56
printInfo.bottomMargin = 56
printInfo.leftMargin = 28
printInfo.rightMargin = 28
printInfo.jobDisposition = .save
```

**Post-processing (simplified):**
```swift
for i in 0..<pageCount {
    let page = document.page(at: i)
    var pageBounds = page.bounds(for: .mediaBox)

    context.beginPage(mediaBox: &pageBounds)
    context.setFillColor(darkColor.cgColor)
    context.fill(pageBounds)           // Background first
    page.draw(with: .mediaBox, to: context)  // Content on top
    context.endPage()
}
```

## Known Limitations

- **Thin white line at top of pages in dark theme**: This is a WebKit rendering artifact that cannot be eliminated without significantly more complex PDF manipulation. Documented in CHANGELOG as known limitation.

## Files

- `src/Printing/PDFExporter.swift` - Main export logic and post-processing
- `WebRenderer/styles/print.css` - Print-specific CSS
- `Tests/PDFExportTests.swift` - Unit tests for filename generation and CSS classes
