/**
 * Tests for the shipped SourcePosMap and Gutter modules.
 * Run with: node WebRenderer/tests/gutter.test.js
 *
 * These load ../src/sourcepos-map.js and ../src/gutter.js into JSDOM, the same
 * way sourcepos.test.js, lineNumbers.test.js, and appHarness.js load the modules
 * they cover. An earlier version of this suite reimplemented both modules inline;
 * the copies drifted from the shipped code (they returned every overlapping
 * element rather than the most specific one, and exposed Gutter as a class), so
 * production regressions could not fail these tests.
 */

const { JSDOM } = require('jsdom');

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

function assertDeepEqual(actual, expected, msg = '') {
    const actualStr = JSON.stringify(actual);
    const expectedStr = JSON.stringify(expected);
    if (actualStr !== expectedStr) {
        throw new Error(`${msg}\n  Expected: ${expectedStr}\n  Actual: ${actualStr}`);
    }
}

function assertTrue(value, msg = '') {
    if (!value) {
        throw new Error(msg || 'Expected true but got false');
    }
}

function assertFalse(value, msg = '') {
    if (value) {
        throw new Error(msg || 'Expected false but got true');
    }
}

function assertNull(value, msg = '') {
    if (value !== null) {
        throw new Error(`${msg}\n  Expected: null\n  Actual: ${value}`);
    }
}

function stubRect(element, { top = 0, height = 0, left = 0, width = 100 }) {
    element.getBoundingClientRect = () => ({
        top, height, left, width, right: left + width, bottom: top + height
    });
}

/**
 * Builds a fresh DOM and loads the production modules into it.
 *
 * JSDOM reports a zero rect for every element, so each block's rect is stubbed to
 * the geometry a test wants; the gutter still reads those positions through
 * getBoundingClientRect exactly as it does in the app.
 */
function setupDOM() {
    const dom = new JSDOM(
        '<!DOCTYPE html><html><body>' +
        '<div id="gutter-container"><div id="git-gutter"></div></div>' +
        '<div id="content-container"></div>' +
        '</body></html>',
        { pretendToBeVisual: true, url: 'https://example.com' }
    );

    const { window } = dom;
    global.window = window;
    global.document = window.document;
    global.requestAnimationFrame = window.requestAnimationFrame.bind(window);
    global.setTimeout = window.setTimeout.bind(window);
    global.clearTimeout = window.clearTimeout.bind(window);

    stubRect(window.document.getElementById('gutter-container'), { top: 0, height: 1000 });

    delete require.cache[require.resolve('../src/sourcepos-map.js')];
    delete require.cache[require.resolve('../src/gutter.js')];
    require('../src/sourcepos-map.js');
    require('../src/gutter.js');

    return window;
}

/**
 * Appends a block carrying `data-sourcepos` to #content-container. Passing
 * `parent` nests it, which is how the shipped map distinguishes a list item from
 * the list containing it.
 */
function addBlock(sourcepos, { top = 0, height = 20, tag = 'p', parent = null } = {}) {
    const element = document.createElement(tag);
    element.setAttribute('data-sourcepos', sourcepos);
    stubRect(element, { top, height });
    (parent || document.getElementById('content-container')).appendChild(element);
    return element;
}

function markers() {
    return Array.from(document.getElementById('git-gutter').children);
}

function markerTypes() {
    return markers().map((marker) => marker.className.replace('gutter-marker gutter-marker--', ''));
}

console.log('\nRunning gutter tests (against the shipped modules)...\n');

// ---------------------------------------------------------------------------
// parseSourcepos / rangesOverlap — exported by the shipped module for testing
// ---------------------------------------------------------------------------

test('testParseSourceposValid', () => {
    setupDOM();
    const result = window.SourcePosMap.parseSourcepos('5:0-10:0');
    assertEqual(result.start, 5, 'Start line should be 5');
    assertEqual(result.end, 10, 'End line should be 10');
});

test('testParseSourceposSingleLine', () => {
    setupDOM();
    const result = window.SourcePosMap.parseSourcepos('3:1-3:20');
    assertEqual(result.start, 3, 'Start line should be 3');
    assertEqual(result.end, 3, 'End line should be 3');
});

test('testParseSourceposNull', () => {
    setupDOM();
    assertNull(window.SourcePosMap.parseSourcepos(null), 'Null input should return null');
    assertNull(window.SourcePosMap.parseSourcepos(''), 'Empty input should return null');
});

test('testParseSourceposInvalid', () => {
    setupDOM();
    assertNull(window.SourcePosMap.parseSourcepos('not-a-sourcepos'), 'Invalid input should return null');
    assertNull(window.SourcePosMap.parseSourcepos('5-10'), 'Missing columns should return null');
});

test('testRangesOverlapFull', () => {
    setupDOM();
    assertTrue(window.SourcePosMap.rangesOverlap(1, 10, 3, 5), 'Contained range should overlap');
});

test('testRangesOverlapPartial', () => {
    setupDOM();
    assertTrue(window.SourcePosMap.rangesOverlap(1, 5, 3, 10), 'Partially overlapping ranges should overlap');
    assertTrue(window.SourcePosMap.rangesOverlap(3, 10, 1, 5), 'Overlap is symmetric');
});

test('testRangesOverlapAdjacent', () => {
    setupDOM();
    assertTrue(window.SourcePosMap.rangesOverlap(1, 5, 5, 10), 'Ranges touching at one line overlap');
});

test('testRangesNoOverlap', () => {
    setupDOM();
    assertFalse(window.SourcePosMap.rangesOverlap(1, 5, 6, 10), 'Disjoint ranges should not overlap');
});

// ---------------------------------------------------------------------------
// SourcePosMap
// ---------------------------------------------------------------------------

test('testSourcePosMapBuild', () => {
    setupDOM();
    addBlock('1:1-3:10');
    addBlock('5:1-7:20');

    const map = new window.SourcePosMap();
    map.build();

    const entries = map.getEntries();
    assertEqual(entries.length, 2, 'Should have 2 entries');
    assertEqual(entries[0].start, 1, 'First entry starts at line 1');
    assertEqual(entries[0].end, 3, 'First entry ends at line 3');
    assertEqual(entries[1].start, 5, 'Second entry starts at line 5');
});

test('testSourcePosMapSkipsElementsWithoutSourcepos', () => {
    setupDOM();
    addBlock('1:1-1:10');
    document.getElementById('content-container').appendChild(document.createElement('p'));

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getEntries().length, 1, 'Elements with no data-sourcepos are ignored');
});

test('testSourcePosMapOverlapFull', () => {
    setupDOM();
    addBlock('1:1-3:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementsForLineRange(1, 3).length, 1, 'Fully covered element should be returned');
});

test('testSourcePosMapOverlapPartial', () => {
    setupDOM();
    addBlock('1:1-5:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementsForLineRange(3, 8).length, 1, 'Partially overlapping element should be returned');
});

test('testSourcePosMapNoOverlap', () => {
    setupDOM();
    addBlock('1:1-3:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementsForLineRange(5, 8).length, 0, 'Disjoint range returns nothing');
});

test('testSourcePosMapMultipleElements', () => {
    setupDOM();
    addBlock('1:1-2:10');
    addBlock('3:1-4:10');
    addBlock('5:1-6:10');

    const map = new window.SourcePosMap();
    map.build();

    const found = map.getElementsForLineRange(2, 5);
    assertEqual(found.length, 3, 'All three overlapping blocks should be returned');
    assertDeepEqual(found.map((entry) => entry.start), [1, 3, 5], 'Returned in line order');
});

/**
 * The shipped map resolves each line to the single most specific element that
 * covers it, so a nested list item wins over the list wrapping it. The old
 * test-local copy returned every overlapping element instead.
 */
test('testSourcePosMapPrefersTheMostSpecificElementPerLine', () => {
    setupDOM();
    const list = addBlock('1:1-3:10', { tag: 'ul' });
    const item = addBlock('2:1-2:10', { tag: 'li', parent: list });

    const map = new window.SourcePosMap();
    map.build();

    const found = map.getElementsForLineRange(2, 2);
    assertEqual(found.length, 1, 'One element per line');
    assertTrue(found[0].element === item, 'The nested list item is more specific than its list');
});

test('testSourcePosMapDeduplicatesAcrossLines', () => {
    setupDOM();
    addBlock('1:1-4:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementsForLineRange(1, 4).length, 1, 'An element spanning the range appears once');
});

// ---------------------------------------------------------------------------
// Deletion anchors
// ---------------------------------------------------------------------------

test('testDeletionAnchorMiddle', () => {
    setupDOM();
    addBlock('1:1-2:10');
    addBlock('5:1-6:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementAtOrAfterLine(3).start, 5, 'Anchors to the next element at or after the line');
});

test('testDeletionAnchorStart', () => {
    setupDOM();
    addBlock('3:1-4:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementAtOrAfterLine(1).start, 3, 'Anchors to the first element');
});

test('testDeletionAnchorEnd', () => {
    setupDOM();
    addBlock('1:1-2:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementAtOrAfterLine(10).start, 1, 'Falls back to the last element');
});

test('testDeletionAnchorExactMatch', () => {
    setupDOM();
    addBlock('1:1-2:10');
    addBlock('5:1-6:10');

    const map = new window.SourcePosMap();
    map.build();

    assertEqual(map.getElementAtOrAfterLine(5).start, 5, 'Exact start line matches its element');
});

test('testDeletionAnchorOnEmptyMapReturnsNull', () => {
    setupDOM();

    const map = new window.SourcePosMap();
    map.build();

    assertNull(map.getElementAtOrAfterLine(1), 'No elements means no anchor');
});

// ---------------------------------------------------------------------------
// Gutter
// ---------------------------------------------------------------------------

test('testGutterMarkerCount', () => {
    setupDOM();
    addBlock('1:1-2:10', { top: 0, height: 40 });
    addBlock('5:1-6:10', { top: 100, height: 40 });

    window.Gutter.update({ addedRanges: [[1, 2]], modifiedRanges: [[5, 6]], deletedAnchors: [] });

    assertEqual(markers().length, 2, 'One marker per changed block');
    assertDeepEqual(markerTypes(), ['added', 'modified'], 'Added markers render before modified');
});

test('testGutterMarkerPosition', () => {
    setupDOM();
    addBlock('1:1-2:10', { top: 120, height: 40 });

    window.Gutter.update({ addedRanges: [[1, 2]], modifiedRanges: [], deletedAnchors: [] });

    const marker = markers()[0];
    assertEqual(marker.style.top, '120px', 'Marker is offset from the gutter container');
    assertEqual(marker.style.height, '40px', 'Marker matches the block height');
});

test('testGutterMarkerPositionIsRelativeToTheGutterContainer', () => {
    setupDOM();
    stubRect(document.getElementById('gutter-container'), { top: 50, height: 1000 });
    addBlock('1:1-2:10', { top: 120, height: 40 });

    window.Gutter.update({ addedRanges: [[1, 2]], modifiedRanges: [], deletedAnchors: [] });

    assertEqual(markers()[0].style.top, '70px', 'Container offset is subtracted');
});

test('testGutterDeletionMarker', () => {
    setupDOM();
    addBlock('1:1-2:10', { top: 0, height: 40 });
    addBlock('5:1-6:10', { top: 100, height: 40 });

    window.Gutter.update({ addedRanges: [], modifiedRanges: [], deletedAnchors: [3] });

    assertDeepEqual(markerTypes(), ['deleted'], 'A deletion anchor renders one deleted marker');
    assertEqual(markers()[0].style.top, '100px', 'Anchored to the following block');
});

test('testGutterCollapsesDeletionMarkersAtTheSamePosition', () => {
    setupDOM();
    addBlock('5:1-6:10', { top: 100, height: 40 });

    window.Gutter.update({ addedRanges: [], modifiedRanges: [], deletedAnchors: [1, 2, 3] });

    assertEqual(markers().length, 1, 'Deletions anchored to the same spot render one marker');
});

test('testGutterScrollUpdate', () => {
    setupDOM();
    const block = addBlock('1:1-2:10', { top: 100, height: 40 });

    window.Gutter.update({ addedRanges: [[1, 2]], modifiedRanges: [], deletedAnchors: [] });
    assertEqual(markers()[0].style.top, '100px', 'Initial position');

    // Scrolling moves the block; re-rendering must follow it.
    stubRect(block, { top: 20, height: 40 });
    window.Gutter.render();

    assertEqual(markers()[0].style.top, '20px', 'Marker follows the block after a scroll');
});

test('testGutterClearRemovesMarkers', () => {
    setupDOM();
    addBlock('1:1-2:10', { top: 0, height: 40 });

    window.Gutter.update({ addedRanges: [[1, 2]], modifiedRanges: [], deletedAnchors: [] });
    assertEqual(markers().length, 1, 'Marker rendered');

    window.Gutter.clear();
    assertEqual(markers().length, 0, 'Markers cleared');

    // Cleared state must survive a re-render.
    window.Gutter.render();
    assertEqual(markers().length, 0, 'Re-rendering after clear draws nothing');
});

test('testGutterUpdateWithNoChangesRendersNothing', () => {
    setupDOM();
    addBlock('1:1-2:10', { top: 0, height: 40 });

    window.Gutter.update({ addedRanges: [], modifiedRanges: [], deletedAnchors: [] });

    assertEqual(markers().length, 0, 'No changes means no markers');
});

// Summary
console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
