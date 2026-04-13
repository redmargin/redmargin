/**
 * Tests for line number generation.
 * Run with: node WebRenderer/tests/lineNumbers.test.js
 */

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

function createMockElement(tagName, sourcepos, top, height) {
    return {
        tagName: tagName.toUpperCase(),
        getAttribute: function(attr) {
            return attr === 'data-sourcepos' ? sourcepos : null;
        },
        getBoundingClientRect: function() {
            return { top, height, left: 0, width: 100 };
        },
        classList: {
            contains: function() {
                return false;
            }
        }
    };
}

function setupMockDOM(elements) {
    const lineContainer = {
        innerHTML: '',
        style: {},
        children: [],
        appendChild: function(el) {
            this.children.push(el);
        }
    };

    global.document = {
        getElementById: function(id) {
            if (id === 'line-numbers-container') return lineContainer;
            if (id === 'gutter-container') {
                return {
                    getBoundingClientRect: function() {
                        return { top: 0, left: 0, width: 44, height: 1000 };
                    }
                };
            }
            if (id === 'content-container') {
                return {
                    querySelectorAll: function(selector) {
                        if (selector === '[data-sourcepos]') {
                            return elements;
                        }
                        return [];
                    }
                };
            }
            return null;
        },
        createElement: function() {
            return {
                className: '',
                textContent: '',
                style: {}
            };
        }
    };

    global.window = {
        addEventListener: function() {}
    };

    delete require.cache[require.resolve('../src/lineNumbers.js')];
    require('../src/lineNumbers.js');

    return lineContainer;
}

function getRenderedLine(container, lineNumber) {
    return container.children.find(function(child) {
        return child.textContent === String(lineNumber);
    });
}

console.log('\nRunning line number tests...\n');

test('testListGapLinesInterpolateBetweenListItems', () => {
    const elements = [
        createMockElement('ul', '68:0-78:0', 100, 240),
        createMockElement('li', '68:0-69:0', 100, 80),
        createMockElement('li', '70:0-71:0', 200, 80),
        createMockElement('li', '72:0-73:0', 300, 80)
    ];

    const container = setupMockDOM(elements);
    global.window.LineNumbers.generate();

    const line69 = getRenderedLine(container, 69);
    const line71 = getRenderedLine(container, 71);

    assertTrue(!!line69, 'Expected line 69 to be rendered');
    assertTrue(!!line71, 'Expected line 71 to be rendered');
    assertEqual(line69.style.top, '153px', 'Line 69 should interpolate between items, not snap to the next bullet');
    assertEqual(line71.style.top, '253px', 'Line 71 should interpolate between items, not snap to the next bullet');
});

test('testTableRowsDoNotOverrideTableLineOffsets', () => {
    const headerRow = {
        getBoundingClientRect: function() {
            return { top: 100, height: 30, left: 0, width: 100 };
        }
    };
    const dataRow = {
        getBoundingClientRect: function() {
            return { top: 130, height: 30, left: 0, width: 100 };
        }
    };
    const table = createMockElement('table', '1:0-3:0', 100, 60);
    table.querySelectorAll = function(selector) {
        if (selector === 'tr') {
            return [headerRow, dataRow];
        }
        return [];
    };

    const elements = [
        table,
        createMockElement('tr', '1:0-1:0', 100, 30),
        createMockElement('tr', '3:0-3:0', 130, 30)
    ];

    const container = setupMockDOM(elements);
    global.window.LineNumbers.generate();

    const line1 = getRenderedLine(container, 1);
    const line2 = getRenderedLine(container, 2);
    const line3 = getRenderedLine(container, 3);

    assertTrue(!!line1, 'Expected line 1 to be rendered');
    assertTrue(!!line2, 'Expected line 2 to be rendered');
    assertTrue(!!line3, 'Expected line 3 to be rendered');
    assertEqual(line1.style.top, '111px', 'Header row should preserve the table row offset');
    assertEqual(line2.style.top, '126px', 'Separator line should be centered between header and body rows');
    assertEqual(line3.style.top, '141px', 'Body row should preserve the table row offset');
});

console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
