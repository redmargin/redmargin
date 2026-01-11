/**
 * Integration test - simulates the full Swift->JS data flow
 * Run with: node WebRenderer/tests/integration.test.js
 */

const markdownit = require('markdown-it');
const taskLists = require('markdown-it-task-lists');
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

function assertTrue(value, msg = '') {
    if (!value) {
        throw new Error(msg || 'Expected true but got false');
    }
}

// Simulate SourcePosMap
function parseSourcepos(sourcepos) {
    if (!sourcepos) return null;
    const match = sourcepos.match(/^(\d+):\d+-(\d+):\d+$/);
    if (!match) return null;
    return {
        start: parseInt(match[1], 10),
        end: parseInt(match[2], 10)
    };
}

function rangesOverlap(aStart, aEnd, bStart, bEnd) {
    return aStart <= bEnd && bStart <= aEnd;
}

function findElementsForLineRange(entries, start, end) {
    var results = [];
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.start > end) break;
        if (rangesOverlap(entry.start, entry.end, start, end)) {
            results.push(entry);
        }
    }
    return results;
}

// Create markdown-it instance
const md = markdownit({ html: true, linkify: true });
md.use(taskLists, { enabled: true, label: true });
md.use(sourceposPlugin);

console.log('\nRunning integration tests...\n');

test('testFullPipelineWithChanges', () => {
    // Simulate the exact JSON that Swift sends
    const swiftPayload = {
        "markdown": "# Title\n\nParagraph on line 3\n\n- Item on line 5\n- Item on line 6",
        "options": { "theme": "light", "basePath": "" },
        "changes": {
            "changedRanges": [[3, 3], [5, 5]],  // Line 3 and line 5 changed
            "deletedAnchors": [],
            "isUntracked": false
        }
    };

    // Render markdown (like index.js does)
    const html = md.render(swiftPayload.markdown);

    // Parse HTML to extract sourcepos attributes (simplified)
    const sourceposRegex = /data-sourcepos="(\d+:\d+-\d+:\d+)"/g;
    const entries = [];
    let match;
    while ((match = sourceposRegex.exec(html)) !== null) {
        const parsed = parseSourcepos(match[1]);
        if (parsed) {
            entries.push({ sourcepos: match[1], start: parsed.start, end: parsed.end });
        }
    }
    entries.sort((a, b) => a.start - b.start);

    console.log('  Entries found:', entries.map(e => e.sourcepos).join(', '));
    assertTrue(entries.length > 0, 'Should find sourcepos entries');

    // Find elements for changed ranges (like gutter.js does)
    const changes = swiftPayload.changes;
    const changedRanges = changes.changedRanges || [];

    let markerCount = 0;
    for (const range of changedRanges) {
        const start = range[0];
        const end = range[1];
        const elements = findElementsForLineRange(entries, start, end);
        console.log(`  Range [${start}, ${end}]: found ${elements.length} element(s)`);
        markerCount += elements.length;
    }

    assertTrue(markerCount > 0, 'Should find elements for changed ranges');
});

test('testJSONParsingMatchesSwiftOutput', () => {
    // This is the exact JSON output from GutterIntegrationTests
    const jsonFromSwift = '{"isUntracked":false,"changedRanges":[[9,9],[47,47],[71,71]],"deletedAnchors":[]}';

    const changes = JSON.parse(jsonFromSwift);

    assertEqual(changes.changedRanges.length, 3, 'Should have 3 changed ranges');
    assertEqual(changes.changedRanges[0][0], 9, 'First range start');
    assertEqual(changes.changedRanges[0][1], 9, 'First range end');
    assertEqual(changes.deletedAnchors.length, 0, 'Should have no deleted anchors');
    assertEqual(changes.isUntracked, false, 'Should not be untracked');
});

test('testChangesNullHandling', () => {
    // Test what happens when changes is null (like before git diff completes)
    const payload = {
        "markdown": "# Test",
        "options": {}
    };

    // Simulate index.js destructuring
    const { markdown, options = {}, changes = null } = payload;

    // Simulate gutter.js update()
    const processedChanges = changes || {};
    const changedRanges = processedChanges.changedRanges || [];
    const deletedAnchors = processedChanges.deletedAnchors || [];

    assertEqual(changedRanges.length, 0, 'Should have empty ranges');
    assertEqual(deletedAnchors.length, 0, 'Should have empty anchors');
});

test('testREADMELineMatching', () => {
    // Test with actual README structure - line 9 is a list item
    const markdown = `# Redmargin

A native macOS Markdown viewer with live rendering.

> **Note:** This is a personal project.

## Features

- **Git gutter** - Shows changed/added/deleted lines compared to HEAD
- **Live Markdown rendering** - View Markdown files
`;

    const html = md.render(markdown);

    // Parse sourcepos
    const sourceposRegex = /data-sourcepos="(\d+:\d+-\d+:\d+)"/g;
    const entries = [];
    let match;
    while ((match = sourceposRegex.exec(html)) !== null) {
        const parsed = parseSourcepos(match[1]);
        if (parsed) {
            entries.push({ sourcepos: match[1], start: parsed.start, end: parsed.end });
        }
    }
    entries.sort((a, b) => a.start - b.start);

    console.log('  All sourcepos entries:');
    entries.forEach(e => console.log(`    ${e.sourcepos} (lines ${e.start}-${e.end})`));

    // Look for line 9
    const elementsAtLine9 = findElementsForLineRange(entries, 9, 9);
    console.log(`  Elements at line 9: ${elementsAtLine9.length}`);

    assertTrue(elementsAtLine9.length > 0, 'Should find element at line 9 (Git gutter item)');
});

test('testEscapedJSONParsing', () => {
    // Simulate the Swift JSON escaping
    const original = '{"markdown":"line1\\nline2","changes":{"changedRanges":[[1,1]]}}';

    // Swift does: jsonString.replacingOccurrences(of: "\\", with: "\\\\")
    //                       .replacingOccurrences(of: "'", with: "\\'")
    // In JS terms that would be:
    const escaped = original.replace(/\\/g, '\\\\').replace(/'/g, "\\'");

    // Then JS evaluates: JSON.parse('...')
    // First the JS string literal is parsed (unescaping \\)
    // Then JSON.parse is called

    // We can't perfectly simulate the string literal parsing, but we can test JSON.parse
    const parsed = JSON.parse(original);

    assertEqual(parsed.markdown, "line1\nline2", 'Newline should be preserved');
    assertEqual(parsed.changes.changedRanges[0][0], 1, 'Range should parse correctly');
});

// Summary
console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
