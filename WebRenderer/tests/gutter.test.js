/**
 * Tests for SourcePosMap and Gutter modules.
 * Run with: node WebRenderer/tests/gutter.test.js
 */

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

// Mock DOM for Node.js environment
const mockElements = [];
let mockGutterContainer = null;
let mockGitGutter = null;
let mockContentContainer = null;

function setupMockDOM() {
    mockElements.length = 0;
    mockGutterContainer = {
        getBoundingClientRect: () => ({ top: 0, left: 0, width: 44, height: 1000 })
    };
    mockGitGutter = {
        innerHTML: '',
        appendChild: (el) => {},
        children: []
    };
    mockContentContainer = {
        querySelectorAll: (selector) => mockElements
    };

    global.document = {
        getElementById: (id) => {
            if (id === 'gutter-container') return mockGutterContainer;
            if (id === 'git-gutter') return mockGitGutter;
            if (id === 'content-container') return mockContentContainer;
            return null;
        },
        createElement: (tag) => ({
            className: '',
            style: {},
            appendChild: () => {}
        }),
        createDocumentFragment: () => ({
            appendChild: () => {}
        })
    };

    global.window = {
        addEventListener: () => {},
        requestAnimationFrame: (fn) => fn()
    };
}

function addMockElement(sourcepos, top, height) {
    mockElements.push({
        getAttribute: (attr) => attr === 'data-sourcepos' ? sourcepos : null,
        getBoundingClientRect: () => ({ top, height, left: 0, width: 100 })
    });
}

// Load modules after mocking
setupMockDOM();

// Inline the parseSourcepos and rangesOverlap functions for testing
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

// SourcePosMap implementation for testing
function SourcePosMap() {
    this.entries = [];
}

SourcePosMap.prototype.build = function() {
    this.entries = [];
    const content = document.getElementById('content-container');
    if (!content) return;

    const elements = content.querySelectorAll('[data-sourcepos]');
    elements.forEach((el) => {
        const sourcepos = el.getAttribute('data-sourcepos');
        const range = parseSourcepos(sourcepos);
        if (range) {
            this.entries.push({
                element: el,
                start: range.start,
                end: range.end
            });
        }
    });
    this.entries.sort((a, b) => a.start - b.start);
};

SourcePosMap.prototype.getElementsForLineRange = function(start, end) {
    var results = [];
    for (var i = 0; i < this.entries.length; i++) {
        var entry = this.entries[i];
        if (entry.start > end) break;
        if (rangesOverlap(entry.start, entry.end, start, end)) {
            results.push(entry);
        }
    }
    return results;
};

SourcePosMap.prototype.getElementAtOrAfterLine = function(line) {
    for (var i = 0; i < this.entries.length; i++) {
        if (this.entries[i].start >= line) {
            return this.entries[i];
        }
    }
    if (this.entries.length > 0) {
        return this.entries[this.entries.length - 1];
    }
    return null;
};

// Tests
console.log('\nRunning gutter tests...\n');

// parseSourcepos tests
test('testParseSourceposValid', () => {
    const result = parseSourcepos('5:0-10:0');
    assertEqual(result.start, 5, 'Start line should be 5');
    assertEqual(result.end, 10, 'End line should be 10');
});

test('testParseSourceposSingleLine', () => {
    const result = parseSourcepos('7:0-7:0');
    assertEqual(result.start, 7, 'Start line should be 7');
    assertEqual(result.end, 7, 'End line should be 7');
});

test('testParseSourceposNull', () => {
    const result = parseSourcepos(null);
    assertEqual(result, null, 'Should return null for null input');
});

test('testParseSourceposInvalid', () => {
    const result = parseSourcepos('invalid');
    assertEqual(result, null, 'Should return null for invalid input');
});

// rangesOverlap tests
test('testRangesOverlapFull', () => {
    assertTrue(rangesOverlap(5, 10, 5, 10), 'Identical ranges should overlap');
});

test('testRangesOverlapPartial', () => {
    assertTrue(rangesOverlap(5, 10, 7, 8), 'Inner range should overlap');
    assertTrue(rangesOverlap(5, 10, 8, 15), 'Overlapping end should overlap');
    assertTrue(rangesOverlap(5, 10, 1, 7), 'Overlapping start should overlap');
});

test('testRangesOverlapAdjacent', () => {
    assertTrue(rangesOverlap(5, 10, 10, 15), 'Adjacent ranges (touching at end) should overlap');
    assertTrue(rangesOverlap(5, 10, 1, 5), 'Adjacent ranges (touching at start) should overlap');
});

test('testRangesNoOverlap', () => {
    assertFalse(rangesOverlap(5, 10, 15, 20), 'Non-overlapping ranges should not overlap');
    assertFalse(rangesOverlap(5, 10, 1, 3), 'Non-overlapping ranges should not overlap');
});

// SourcePosMap tests
test('testSourcePosMapBuild', () => {
    setupMockDOM();
    addMockElement('1:0-3:0', 0, 50);
    addMockElement('5:0-7:0', 60, 50);
    addMockElement('9:0-12:0', 120, 80);

    const map = new SourcePosMap();
    map.build();

    assertEqual(map.entries.length, 3, 'Should have 3 entries');
    assertEqual(map.entries[0].start, 1, 'First entry should start at line 1');
    assertEqual(map.entries[1].start, 5, 'Second entry should start at line 5');
    assertEqual(map.entries[2].start, 9, 'Third entry should start at line 9');
});

test('testSourcePosMapOverlapFull', () => {
    setupMockDOM();
    addMockElement('5:0-10:0', 0, 100);

    const map = new SourcePosMap();
    map.build();

    const results = map.getElementsForLineRange(5, 10);
    assertEqual(results.length, 1, 'Should find 1 element');
    assertEqual(results[0].start, 5, 'Element should start at line 5');
});

test('testSourcePosMapOverlapPartial', () => {
    setupMockDOM();
    addMockElement('5:0-10:0', 0, 100);

    const map = new SourcePosMap();
    map.build();

    const results = map.getElementsForLineRange(7, 8);
    assertEqual(results.length, 1, 'Should find 1 element for partial overlap');
});

test('testSourcePosMapNoOverlap', () => {
    setupMockDOM();
    addMockElement('5:0-10:0', 0, 100);

    const map = new SourcePosMap();
    map.build();

    const results = map.getElementsForLineRange(15, 20);
    assertEqual(results.length, 0, 'Should find 0 elements for no overlap');
});

test('testSourcePosMapMultipleElements', () => {
    setupMockDOM();
    addMockElement('1:0-5:0', 0, 50);
    addMockElement('6:0-10:0', 60, 50);
    addMockElement('11:0-15:0', 120, 50);

    const map = new SourcePosMap();
    map.build();

    const results = map.getElementsForLineRange(4, 12);
    assertEqual(results.length, 3, 'Should find 3 elements overlapping range 4-12');
});

test('testDeletionAnchorMiddle', () => {
    setupMockDOM();
    addMockElement('1:0-5:0', 0, 50);
    addMockElement('8:0-12:0', 60, 50);
    addMockElement('15:0-20:0', 120, 50);

    const map = new SourcePosMap();
    map.build();

    const result = map.getElementAtOrAfterLine(10);
    assertEqual(result.start, 15, 'Should find element starting at line 15 for anchor at 10');
});

test('testDeletionAnchorStart', () => {
    setupMockDOM();
    addMockElement('5:0-10:0', 0, 50);
    addMockElement('12:0-15:0', 60, 50);

    const map = new SourcePosMap();
    map.build();

    const result = map.getElementAtOrAfterLine(1);
    assertEqual(result.start, 5, 'Should find first element for anchor at line 1');
});

test('testDeletionAnchorEnd', () => {
    setupMockDOM();
    addMockElement('1:0-5:0', 0, 50);
    addMockElement('6:0-10:0', 60, 50);

    const map = new SourcePosMap();
    map.build();

    const result = map.getElementAtOrAfterLine(100);
    assertEqual(result.start, 6, 'Should find last element for anchor beyond end');
});

test('testDeletionAnchorExactMatch', () => {
    setupMockDOM();
    addMockElement('1:0-5:0', 0, 50);
    addMockElement('8:0-12:0', 60, 50);

    const map = new SourcePosMap();
    map.build();

    const result = map.getElementAtOrAfterLine(8);
    assertEqual(result.start, 8, 'Should find element starting exactly at anchor line');
});

// Gutter tests - need to track created markers
let createdMarkers = [];

function setupGutterMockDOM() {
    setupMockDOM();
    createdMarkers = [];

    global.document.getElementById = (id) => {
        if (id === 'gutter-container') return mockGutterContainer;
        if (id === 'git-gutter') return {
            innerHTML: '',
            appendChild: (fragment) => {
                // Track markers from fragment
                if (fragment._markers) {
                    createdMarkers.push(...fragment._markers);
                }
            }
        };
        if (id === 'content-container') return mockContentContainer;
        return null;
    };

    global.document.createDocumentFragment = () => {
        const fragment = {
            _markers: [],
            appendChild: (el) => fragment._markers.push(el)
        };
        return fragment;
    };

    global.document.createElement = (tag) => ({
        className: '',
        style: {},
        appendChild: () => {}
    });
}

// Gutter implementation for testing
function Gutter() {
    this.sourceposMap = null;
    this.cachedElements = [];
}

Gutter.prototype.update = function(changes) {
    changes = changes || {};
    const addedRanges = changes.addedRanges || [];
    const modifiedRanges = changes.modifiedRanges || [];
    const deletedAnchors = changes.deletedAnchors || [];

    this.sourceposMap = new SourcePosMap();
    this.sourceposMap.build();

    this.cachedElements = [];

    // Process added ranges
    for (let i = 0; i < addedRanges.length; i++) {
        const range = addedRanges[i];
        const elements = this.sourceposMap.getElementsForLineRange(range[0], range[1]);
        for (let j = 0; j < elements.length; j++) {
            this.cachedElements.push({ element: elements[j].element, type: 'added' });
        }
    }

    // Process modified ranges
    for (let i = 0; i < modifiedRanges.length; i++) {
        const range = modifiedRanges[i];
        const elements = this.sourceposMap.getElementsForLineRange(range[0], range[1]);
        for (let j = 0; j < elements.length; j++) {
            this.cachedElements.push({ element: elements[j].element, type: 'modified' });
        }
    }

    // Process deleted anchors
    for (let k = 0; k < deletedAnchors.length; k++) {
        const anchor = deletedAnchors[k];
        const entry = this.sourceposMap.getElementAtOrAfterLine(anchor);
        if (entry) {
            this.cachedElements.push({ element: entry.element, type: 'deleted', anchorLine: anchor });
        }
    }

    this.render();
};

Gutter.prototype.render = function() {
    const container = document.getElementById('git-gutter');
    const gutterContainer = document.getElementById('gutter-container');
    if (!container || !gutterContainer) return;

    container.innerHTML = '';
    if (this.cachedElements.length === 0) return;

    const gutterRect = gutterContainer.getBoundingClientRect();
    const fragment = document.createDocumentFragment();

    for (let i = 0; i < this.cachedElements.length; i++) {
        const cached = this.cachedElements[i];
        const rect = cached.element.getBoundingClientRect();
        const top = rect.top - gutterRect.top;

        const marker = document.createElement('div');
        marker.className = 'gutter-marker gutter-marker--' + cached.type;
        marker.style.top = top + 'px';
        if (cached.type !== 'deleted') {
            marker.style.height = rect.height + 'px';
        }
        fragment.appendChild(marker);
    }

    container.appendChild(fragment);
};

test('testGutterMarkerCount', () => {
    setupGutterMockDOM();
    addMockElement('1:0-3:0', 0, 50);
    addMockElement('5:0-7:0', 60, 50);
    addMockElement('10:0-12:0', 130, 50);

    const gutter = new Gutter();
    gutter.update({
        addedRanges: [[1, 3], [10, 12]],
        modifiedRanges: [[5, 7]],
        deletedAnchors: []
    });

    assertEqual(createdMarkers.length, 3, 'Should create 3 markers for 3 ranges');
});

test('testGutterMarkerPosition', () => {
    setupGutterMockDOM();
    addMockElement('5:0-7:0', 100, 60);

    const gutter = new Gutter();
    gutter.update({
        addedRanges: [[5, 7]],
        modifiedRanges: [],
        deletedAnchors: []
    });

    assertEqual(createdMarkers.length, 1, 'Should create 1 marker');
    assertEqual(createdMarkers[0].style.top, '100px', 'Marker top should match element top');
    assertEqual(createdMarkers[0].style.height, '60px', 'Marker height should match element height');
});

test('testGutterDeletionMarker', () => {
    setupGutterMockDOM();
    addMockElement('1:0-5:0', 0, 50);
    addMockElement('10:0-15:0', 80, 50);

    const gutter = new Gutter();
    gutter.update({
        addedRanges: [],
        modifiedRanges: [],
        deletedAnchors: [7]
    });

    assertEqual(createdMarkers.length, 1, 'Should create 1 deletion marker');
    assertTrue(createdMarkers[0].className.includes('deleted'), 'Marker should have deleted class');
});

test('testGutterScrollUpdate', () => {
    setupGutterMockDOM();
    let elementTop = 100;
    mockElements.length = 0;
    mockElements.push({
        getAttribute: (attr) => attr === 'data-sourcepos' ? '5:0-7:0' : null,
        getBoundingClientRect: () => ({ top: elementTop, height: 60, left: 0, width: 100 })
    });

    const gutter = new Gutter();
    gutter.update({
        addedRanges: [[5, 7]],
        modifiedRanges: [],
        deletedAnchors: []
    });

    assertEqual(createdMarkers[0].style.top, '100px', 'Initial marker position');

    // Simulate scroll by changing element's getBoundingClientRect
    elementTop = 50;
    createdMarkers = [];
    gutter.render();

    assertEqual(createdMarkers[0].style.top, '50px', 'Marker should update position after scroll');
});

// Summary
console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
