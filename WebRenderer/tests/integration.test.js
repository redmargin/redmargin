/**
 * Integration test - simulates the full Swift->JS data flow
 * Run with: node WebRenderer/tests/integration.test.js
 */

const markdownit = require('markdown-it');
const taskLists = require('markdown-it-task-lists');
const sourceposPlugin = require('../src/sourcepos.js');
const { createAppHarness, flushPromises } = require('./appHarness');

let passed = 0;
let failed = 0;

async function test(name, fn) {
    try {
        await fn();
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

const md = markdownit({ html: true, linkify: true });
md.use(taskLists, { enabled: true, label: true });
md.use(sourceposPlugin);

console.log('\nRunning integration tests...\n');

async function run() {
    await test('testFullPipelineWithChanges', async () => {
        const swiftPayload = {
            "markdown": "# Title\n\nParagraph on line 3\n\n- Item on line 5\n- Item on line 6",
            "options": { "theme": "light", "basePath": "" },
            "changes": {
                "changedRanges": [[3, 3], [5, 5]],
                "deletedAnchors": [],
                "isUntracked": false
            }
        };

        const html = md.render(swiftPayload.markdown);
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

    await test('testJSONParsingMatchesSwiftOutput', async () => {
        const jsonFromSwift = '{"isUntracked":false,"changedRanges":[[9,9],[47,47],[71,71]],"deletedAnchors":[]}';
        const changes = JSON.parse(jsonFromSwift);

        assertEqual(changes.changedRanges.length, 3, 'Should have 3 changed ranges');
        assertEqual(changes.changedRanges[0][0], 9, 'First range start');
        assertEqual(changes.changedRanges[0][1], 9, 'First range end');
        assertEqual(changes.deletedAnchors.length, 0, 'Should have no deleted anchors');
        assertEqual(changes.isUntracked, false, 'Should not be untracked');
    });

    await test('testChangesNullHandling', async () => {
        const payload = {
            "markdown": "# Test",
            "options": {}
        };

        const { markdown, options = {}, changes = null } = payload;
        const processedChanges = changes || {};
        const changedRanges = processedChanges.changedRanges || [];
        const deletedAnchors = processedChanges.deletedAnchors || [];

        void markdown;
        void options;
        assertEqual(changedRanges.length, 0, 'Should have empty ranges');
        assertEqual(deletedAnchors.length, 0, 'Should have empty anchors');
    });

    await test('testREADMELineMatching', async () => {
        const markdown = `# Redmargin

A native macOS Markdown viewer with live rendering.

## Features

- **Git gutter** - Shows changed/added/deleted lines compared to HEAD
- **Live Markdown rendering** - View Markdown files
`;

        const html = md.render(markdown);
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

        const elementsAtLine8 = findElementsForLineRange(entries, 8, 8);
        console.log(`  Elements at line 8: ${elementsAtLine8.length}`);
        assertTrue(elementsAtLine8.length > 0, 'Should find element at line 8 (Git gutter item)');
    });

    await test('testEscapedJSONParsing', async () => {
        const original = '{"markdown":"line1\\nline2","changes":{"changedRanges":[[1,1]]}}';
        const parsed = JSON.parse(original);

        assertEqual(parsed.markdown, "line1\nline2", 'Newline should be preserved');
        assertEqual(parsed.changes.changedRanges[0][0], 1, 'Range should parse correctly');
    });

    await test('testDocumentWithNoMermaidBlocksRendersNormally', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '```swift\nlet x = 1\n```',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();
        await harness.window.MermaidRenderer.renderBlocks();

        assertEqual(harness.document.querySelectorAll('.mermaid-block').length, 0, 'Regular code blocks should not become Mermaid blocks');
    });

    await test('testMermaidFenceParticipatesInGutterRangeMatching', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '```mermaid\ngraph TD\n  A-->B\n```',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();

        const sourcePosMap = new harness.window.SourcePosMap();
        sourcePosMap.build();
        const matches = sourcePosMap.getElementsForLineRange(2, 3);

        assertTrue(
            matches.some(entry => entry.element.classList.contains('mermaid-block')),
            'Expected Mermaid block to participate in gutter source range matching'
        );
    });

    await test('testPandocRawHtmlFenceRendersThroughSanitizer', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '```{=html}\n' +
                '<div class="sevbar" onclick="evil()">\n' +
                '  <div class="cell c-critical"><span class="n">2</span><span class="l">Critical</span></div>\n' +
                '  <script>alert(1)</script>\n' +
                '  <a href="javascript:alert(1)">bad</a>\n' +
                '</div>\n' +
                '```',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();

        const rawBlock = harness.document.querySelector('.raw-html-block');
        const sevbar = harness.document.querySelector('.raw-html-block .sevbar');
        const critical = harness.document.querySelector('.sevbar .c-critical');
        const badLink = harness.document.querySelector('.sevbar a');

        assertTrue(!!rawBlock, 'Expected Pandoc raw HTML fence to render as sanitized HTML');
        assertTrue(!!sevbar, 'Expected severity bar markup to be preserved');
        assertTrue(!!critical, 'Expected severity class markup to be preserved');
        assertEqual(rawBlock.getAttribute('data-sourcepos'), '1:1-7:3', 'Raw HTML fence should preserve source position');
        assertTrue(!harness.document.querySelector('.raw-html-block pre'), 'Raw HTML fence should not render as a code block');
        assertTrue(!sevbar.hasAttribute('onclick'), 'Event handlers should be stripped from raw HTML');
        assertTrue(!harness.document.querySelector('.raw-html-block script'), 'Scripts should be stripped from raw HTML');
        assertTrue(!!badLink && !badLink.hasAttribute('href'), 'Unsafe href should be stripped from raw HTML');
    });

    await test('testRegularHtmlFenceStillRendersAsCode', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '```html\n<div class="sevbar">text</div>\n```',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();

        assertTrue(!!harness.document.querySelector('pre code'), 'Regular html fences should remain code blocks');
        assertEqual(harness.document.querySelectorAll('.sevbar').length, 0, 'Regular html fences should not render raw HTML');
    });

    await test('testSourcePosMapPrefersListItemsOverListContainer', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '- one\n- two\n- three',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();

        const sourcePosMap = new harness.window.SourcePosMap();
        sourcePosMap.build();
        const matches = sourcePosMap.getElementsForLineRange(2, 2);

        assertTrue(matches.some(entry => entry.element.tagName === 'LI'),
            'Expected the matching list item to be returned');
        assertTrue(matches.every(entry => entry.element.tagName !== 'UL'),
            'List container should not shadow the specific list item');
    });

    await test('testSourcePosMapPrefersTableRowsOverTableForRowLines', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '| A | B |\n| - | - |\n| 1 | 2 |',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();

        const sourcePosMap = new harness.window.SourcePosMap();
        sourcePosMap.build();
        const rowMatches = sourcePosMap.getElementsForLineRange(1, 1);
        const separatorMatches = sourcePosMap.getElementsForLineRange(2, 2);

        assertTrue(rowMatches.some(entry => entry.element.tagName === 'TR'),
            'Expected table row lines to map to their row element');
        assertTrue(rowMatches.every(entry => entry.element.tagName !== 'TABLE'),
            'Table container should not shadow a specific row line');
        assertTrue(separatorMatches.length === 1 && separatorMatches[0].element.tagName === 'TABLE',
            'Separator lines should fall back to the table container');
    });

    await test('testDeletionAnchorPrefersSpecificElementAtSharedStartLine', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '- one\n- two',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();

        const sourcePosMap = new harness.window.SourcePosMap();
        sourcePosMap.build();
        const match = sourcePosMap.getElementAtOrAfterLine(1);

        assertEqual(match.element.tagName, 'LI',
            'Deletion anchors should prefer the specific list item over the list container');
    });

    await test('testFrontMatterOffsetAppliesToMermaidSourcepos', async () => {
        const harness = createAppHarness({ disableMermaid: true });

        harness.window.App.render({
            markdown: '---\ntitle: Test\n---\n```mermaid\ngraph TD\n  A-->B\n```',
            options: { theme: 'light', basePath: '' }
        });
        await flushPromises();
        await flushPromises();

        const block = harness.document.querySelector('.mermaid-block');
        assertTrue(!!block, 'Expected Mermaid block to be rendered');
        assertEqual(
            block.getAttribute('data-sourcepos'),
            '4:1-7:3',
            'Front matter offset should apply to Mermaid source positions'
        );
    });

    console.log(`\n${passed} passed, ${failed} failed\n`);
    process.exit(failed > 0 ? 1 : 0);
}

run();
