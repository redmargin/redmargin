# Table Column Width Optimization

## Problem

GFM tables rendered with `width: 100%` in a WKWebView use CSS auto table layout, which distributes surplus width proportionally to ALL columns. This causes:

- Short-content columns ("Yes", "No", "any") become ~130px when they only need ~50px
- Long-text columns don't get enough relative space
- Code spans in narrow columns appear visually "indented" when wrapping to a new line
- Headers with moderate-length text break mid-word when squeezed

No CSS-only solution exists. GitHub, Typora, and Obsidian all have the same issue or use non-HTML rendering. Content-aware column sizing requires post-render JavaScript measurement.

## Algorithm

The `optimizeTableWidths()` function in `WebRenderer/src/index.js` implements a min-content/max-content distribution algorithm, modeled after CSS Grid's intrinsic sizing.

### Phase 1: Measure max-content widths

Set all cells to `white-space: nowrap` and the table to `width: auto`. Force a layout pass, then measure each column's `scrollWidth` across all rows. The maximum per column is the **max-content width** — the ideal width where nothing wraps at all.

### Phase 2: Measure min-content widths

Remove the nowrap, set the table to `width: 0px`. The browser wraps text at word boundaries (its default behavior). Force layout, then measure `scrollWidth` per column again. The maximum per column is the **min-content width** — the width of the longest word, including cell padding. This is the absolute minimum before mid-word breaks occur.

These are the browser's own layout calculations. No arbitrary thresholds, percentages, or heuristics.

### Phase 3: Distribute space

Three cases:

1. **Everything fits** (`totalMaxContent <= availWidth`): Use `width: auto`. The browser handles it perfectly.

2. **Normal case** (`totalMinContent < availWidth < totalMaxContent`): Each column starts at its min-content width. The remaining space (`availWidth - totalMinContent`) is distributed proportionally to each column's **growth potential**: `maxContent[i] - minContent[i]`.

3. **Extremely tight** (`totalMinContent >= availWidth`): Fall back to `width: 100%` and let the browser handle it. Mid-word breaks are unavoidable.

For the normal case, a `<colgroup>` with pixel widths is injected and the table switches to `table-layout: fixed` for precise control.

### Why growth-proportional distribution works

| Column example | min-content | max-content | growth | Behavior |
|---|---|---|---|---|
| "Yes"/"No" body, "Adds" header | ~50px | ~50px | 0 | Stays tight, gets no extra space |
| "any" body, "Starting mode" header | ~95px | ~140px | 45px | Gets moderate extra space |
| Long paragraph, "Notes" header | ~85px | ~400px | 315px | Gets the lion's share |

Columns with near-zero growth potential (content already fits at min-content) naturally stay compact. Columns with lots of content that could benefit from more space get proportionally more. This handles both short-body/long-header and long-body/short-header cases without special casing.

## Supporting CSS Changes

| Rule | Purpose |
|---|---|
| `td code, th code { padding: 0.1em 0.2em }` | Tighter padding on inline code in table cells prevents visual indent when code wraps to a new line |
| `style` attr on `th`/`td` (sanitizer) | Allows `text-align` style from GFM column alignment syntax (`:---`, `:---:`, `---:`) |
| `padding: 6px 13px` on cells | Matches GitHub's cell padding |

## Test Coverage

`testTableColumnWidthsAreCompact` in `Tests/MarkdownWebViewTests.swift`:

- Renders a 5-column GFM table in a real WKWebView
- Calls `window.App.render()` with the table markdown
- Measures column widths via `getBoundingClientRect()` in JavaScript
- Asserts:
  - Short column ("Adds" with "Yes"/"No") < 100px
  - Short column is the narrowest
  - No single column exceeds 55% of container width
  - Short column is less than half the widest column

## Failed Approaches (for reference)

1. **CSS `display: block; width: max-content; max-width: 100%`** (GitHub Primer CSS) — only helps for tables narrower than the container; equivalent to `width: 100%` for wide tables
2. **Fixed/flex binary classifier** (columns under 100px get exact width, rest share proportionally) — short-content columns work, but header-heavy columns get squeezed because proportional distribution is dominated by the long-text column
3. **Header `white-space: nowrap`** — prevents header wrapping entirely, but causes overflow/overlap in fixed layout when columns are compressed
4. **Percentage-based header floor** (60-75% of header natural width) — arbitrary magic numbers; works for one table, breaks for another
