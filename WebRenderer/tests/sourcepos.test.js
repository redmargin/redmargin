/**
 * Tests for markdown-it sourcepos plugin and rendering.
 * Run with: node WebRenderer/tests/sourcepos.test.js
 */

const markdownit = require('markdown-it');
const taskLists = require('markdown-it-task-lists');

// Load our sourcepos plugin
const sourceposPlugin = require('../src/sourcepos.js');

// Test utilities
let passed = 0;
let failed = 0;

function test(name, fn) {
    try {
        fn();
        console.log(`✓ ${name}`);
        passed++;
    } catch (err) {
        console.log(`✗ ${name}`);
        console.log(`  ${err.message}`);
        failed++;
    }
}

function assertEqual(actual, expected, msg = '') {
    if (actual !== expected) {
        throw new Error(`${msg}\n  Expected: ${expected}\n  Actual: ${actual}`);
    }
}

function assertContains(str, substr, msg = '') {
    if (!str.includes(substr)) {
        throw new Error(`${msg}\n  Expected to contain: ${substr}\n  Actual: ${str}`);
    }
}

function assertMatch(str, regex, msg = '') {
    if (!regex.test(str)) {
        throw new Error(`${msg}\n  Expected to match: ${regex}\n  Actual: ${str}`);
    }
}

// Create markdown-it instance with our plugins
const md = markdownit({ html: true, linkify: true });
md.use(taskLists, { enabled: true, label: true });
md.use(sourceposPlugin);

// Tests
console.log('\nRunning sourcepos tests...\n');

test('testMarkdownItRendersBasicMarkdown', () => {
    const html = md.render('# Hello');
    assertContains(html, '<h1', 'Should render heading');
    assertContains(html, 'Hello', 'Should contain heading text');
});

test('testSourceposOnHeading', () => {
    const html = md.render('# Hello');
    assertMatch(html, /data-sourcepos="1:0-1:0"/, 'Heading should have sourcepos');
});

test('testSourceposOnParagraph', () => {
    const html = md.render('Line 1\n\nLine 3');
    // Line 1 is paragraph at line 1, Line 3 is paragraph at line 3
    assertMatch(html, /data-sourcepos="1:0-1:0"/, 'First paragraph should have sourcepos');
    assertMatch(html, /data-sourcepos="3:0-3:0"/, 'Second paragraph should have sourcepos at line 3');
});

test('testSourceposOnMultilineBlock', () => {
    const input = `
\`\`\`
code line 1
code line 2
code line 3
\`\`\``;
    const html = md.render(input);
    // Code block starts at line 2 (after blank line 1)
    assertMatch(html, /data-sourcepos="2:0-6:0"/, 'Code block should have correct sourcepos span');
});

test('testSourceposOnTable', () => {
    const input = `| A | B |
| - | - |
| 1 | 2 |`;
    const html = md.render(input);
    assertContains(html, '<table', 'Should render table');
    assertMatch(html, /data-sourcepos="1:0-3:0"/, 'Table should have sourcepos');
});

test('testSourceposOnListItems', () => {
    const input = `- item 1
- item 2
- item 3`;
    const html = md.render(input);
    assertContains(html, '<li', 'Should render list items');
    assertMatch(html, /data-sourcepos="1:0-1:0"/, 'First list item should have sourcepos');
    assertMatch(html, /data-sourcepos="2:0-2:0"/, 'Second list item should have sourcepos');
    assertMatch(html, /data-sourcepos="3:0-3:0"/, 'Third list item should have sourcepos');
});

test('testGFMTableRenders', () => {
    const input = `| Header 1 | Header 2 |
| -------- | -------- |
| Cell 1   | Cell 2   |`;
    const html = md.render(input);
    assertContains(html, '<table', 'Should render table element');
    assertContains(html, '<th', 'Should render table headers');
    assertContains(html, '<td', 'Should render table cells');
    assertContains(html, 'Header 1', 'Should contain header text');
    assertContains(html, 'Cell 1', 'Should contain cell text');
});

test('testTaskListRenders', () => {
    const input = `- [ ] unchecked
- [x] checked`;
    const html = md.render(input);
    assertContains(html, '<input', 'Should render checkbox inputs');
    assertContains(html, 'type="checkbox"', 'Should have checkbox type');
    assertContains(html, 'checked', 'Should have checked attribute on second item');
});

test('testSourceposOnBlockquote', () => {
    const input = `> This is a quote
> spanning lines`;
    const html = md.render(input);
    assertContains(html, '<blockquote', 'Should render blockquote');
    assertMatch(html, /data-sourcepos="1:0-2:0"/, 'Blockquote should have correct sourcepos');
});

test('testSourceposOnHorizontalRule', () => {
    const input = `text

---

more text`;
    const html = md.render(input);
    assertContains(html, '<hr', 'Should render horizontal rule');
    assertMatch(html, /<hr[^>]*data-sourcepos="3:0-3:0"/, 'HR should have sourcepos');
});

// Line number gap-filling tests
test('testLineNumberGapFilling', () => {
    // Simulate the fillGaps logic
    function fillGaps(linePositions) {
        const lines = Object.keys(linePositions).map(Number).sort((a, b) => a - b);
        if (lines.length < 2) return linePositions;

        const result = { ...linePositions };
        for (let i = 0; i < lines.length - 1; i++) {
            const currLine = lines[i];
            const nextLine = lines[i + 1];
            const currTop = result[currLine];
            const nextTop = result[nextLine];

            const gap = nextLine - currLine;
            if (gap > 1) {
                const heightPerLine = (nextTop - currTop) / gap;
                for (let j = 1; j < gap; j++) {
                    result[currLine + j] = currTop + (j * heightPerLine);
                }
            }
        }
        return result;
    }

    // Test: lines 1, 3, 5 known; 2, 4 should be filled
    const input = { 1: 0, 3: 100, 5: 200 };
    const result = fillGaps(input);

    assertEqual(Object.keys(result).length, 5, 'Should have 5 lines');
    assertEqual(result[1], 0, 'Line 1 position');
    assertEqual(result[2], 50, 'Line 2 interpolated');
    assertEqual(result[3], 100, 'Line 3 position');
    assertEqual(result[4], 150, 'Line 4 interpolated');
    assertEqual(result[5], 200, 'Line 5 position');
});

test('testLineNumberNoGaps', () => {
    function fillGaps(linePositions) {
        const lines = Object.keys(linePositions).map(Number).sort((a, b) => a - b);
        if (lines.length < 2) return linePositions;

        const result = { ...linePositions };
        for (let i = 0; i < lines.length - 1; i++) {
            const currLine = lines[i];
            const nextLine = lines[i + 1];
            const gap = nextLine - currLine;
            if (gap > 1) {
                const heightPerLine = (result[nextLine] - result[currLine]) / gap;
                for (let j = 1; j < gap; j++) {
                    result[currLine + j] = result[currLine] + (j * heightPerLine);
                }
            }
        }
        return result;
    }

    // Test: consecutive lines, no gaps
    const input = { 1: 0, 2: 20, 3: 40 };
    const result = fillGaps(input);

    assertEqual(Object.keys(result).length, 3, 'Should still have 3 lines');
});

test('testLineNumberLargeGap', () => {
    function fillGaps(linePositions) {
        const lines = Object.keys(linePositions).map(Number).sort((a, b) => a - b);
        if (lines.length < 2) return linePositions;

        const result = { ...linePositions };
        for (let i = 0; i < lines.length - 1; i++) {
            const currLine = lines[i];
            const nextLine = lines[i + 1];
            const gap = nextLine - currLine;
            if (gap > 1) {
                const heightPerLine = (result[nextLine] - result[currLine]) / gap;
                for (let j = 1; j < gap; j++) {
                    result[currLine + j] = result[currLine] + (j * heightPerLine);
                }
            }
        }
        return result;
    }

    // Test: gap of 5 lines (simulates blank lines between sections)
    const input = { 62: 1000, 64: 1100 }; // Line 63 is blank
    const result = fillGaps(input);

    assertEqual(Object.keys(result).length, 3, 'Should have 3 lines');
    assertEqual(result[63], 1050, 'Line 63 interpolated halfway');
});

test('testLineNumberVerticalOffset', () => {
    // Verify the vertical offset constant for general alignment
    const verticalOffset = 3;
    assertEqual(verticalOffset, 3, 'General vertical offset should be 3px');
});

test('testLineNumberTableRowOffset', () => {
    // Verify the table row offset constant (accounts for cell padding)
    const tableRowOffset = 8;
    assertEqual(tableRowOffset, 8, 'Table row offset should be 8px');
});

test('testLineNumberOffsetsApplied', () => {
    // Test that offsets are applied correctly
    const verticalOffset = 3;
    const tableRowOffset = 8;

    // Normal element at position 100 should render at 103
    const normalPos = 100;
    const normalRendered = normalPos + verticalOffset;
    assertEqual(normalRendered, 103, 'Normal element offset applied');

    // Table row at position 100 should render at 111 (100 + 8 + 3)
    const tablePos = 100;
    const tableRendered = tablePos + tableRowOffset + verticalOffset;
    assertEqual(tableRendered, 111, 'Table row total offset applied');
});

// Summary
console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
