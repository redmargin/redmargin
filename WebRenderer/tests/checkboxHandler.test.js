/**
 * Tests for the task-list checkbox handler.
 * Run with: node WebRenderer/tests/checkboxHandler.test.js
 *
 * The line this handler reports is the line Swift rewrites in the user's file,
 * so every assertion here is about which source line a given checkbox maps to.
 */

const { createAppHarness, flushPromises } = require('./appHarness');

// Test utilities
let passed = 0;
let failed = 0;

// Each harness installs fresh globals, so the tests run one at a time.
const pending = [];

function test(name, fn) {
    pending.push({ name, fn });
}

async function runAll() {
    for (const { name, fn } of pending) {
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
}

function assertEqual(actual, expected, msg = '') {
    if (actual !== expected) {
        throw new Error(`${msg}\n  Expected: ${expected}\n  Actual: ${actual}`);
    }
}

function assertDeepEqual(actual, expected, msg = '') {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a !== e) {
        throw new Error(`${msg}\n  Expected: ${e}\n  Actual: ${a}`);
    }
}

console.log('\nRunning checkbox handler tests...\n');

/**
 * Render markdown through the real app pipeline, attach the handler, and capture
 * everything it posts to Swift.
 */
async function renderWithHandler(markdown) {
    const harness = createAppHarness({ disableMermaid: true });
    const posted = [];

    harness.window.webkit = {
        messageHandlers: {
            checkboxToggle: {
                postMessage: function(message) {
                    posted.push(message);
                }
            }
        }
    };

    delete require.cache[require.resolve('../src/checkboxHandler.js')];
    require('../src/checkboxHandler.js');

    harness.window.App.render({ markdown, options: { theme: 'light', basePath: '' } });
    await flushPromises();
    await flushPromises();

    return { harness, posted };
}

function clickCheckbox(harness, checkbox) {
    checkbox.dispatchEvent(new harness.window.MouseEvent('click', { bubbles: true, cancelable: true }));
}

function checkboxes(harness) {
    return [...harness.document.querySelectorAll('input.task-list-item-checkbox')];
}

// === List checkboxes ===

const LIST_DOC = [
    '# Title',            // line 1
    '',                   // line 2
    '- [ ] first task',   // line 3
    '- [x] second task',  // line 4
    ''
].join('\n');

test('testListCheckboxReportsItsOwnSourceLine', async () => {
    const { harness, posted } = await renderWithHandler(LIST_DOC);
    const boxes = checkboxes(harness);
    assertEqual(boxes.length, 2, 'Both list checkboxes should render');

    clickCheckbox(harness, boxes[0]);
    assertDeepEqual(posted, [{ line: 3, checked: true }], 'First item lives on line 3 and is being checked');
});

test('testSecondListCheckboxReportsItsOwnLineNotTheFirst', async () => {
    const { harness, posted } = await renderWithHandler(LIST_DOC);
    const boxes = checkboxes(harness);

    clickCheckbox(harness, boxes[1]);
    assertDeepEqual(posted, [{ line: 4, checked: false }], 'Second item lives on line 4 and is being unchecked');
});

test('testListCheckboxDoesNotToggleDuringTextSelection', async () => {
    const { harness, posted } = await renderWithHandler(LIST_DOC);
    const boxes = checkboxes(harness);

    // A drag that ends on the checkbox leaves a non-collapsed selection.
    harness.window.getSelection = function() {
        return { isCollapsed: false };
    };
    clickCheckbox(harness, boxes[0]);

    assertEqual(posted.length, 0, 'A selection drag must not toggle the checkbox');
    assertEqual(boxes[0].checked, false, 'The checkbox must be left as it was');
});

// === Table checkboxes ===

const TABLE_DOC = [
    '# Title',              // line 1
    '',                     // line 2
    '| done | item |',      // line 3
    '|---|---|',            // line 4
    '| [ ] | table one |',  // line 5
    '| [x] | table two |',  // line 6
    ''
].join('\n');

test('testTableCheckboxReportsItsRowSourceLine', async () => {
    const { harness, posted } = await renderWithHandler(TABLE_DOC);
    const boxes = checkboxes(harness);
    assertEqual(boxes.length, 2, 'Both table checkboxes should render');

    clickCheckbox(harness, boxes[0]);
    assertDeepEqual(posted, [{ line: 5, checked: true }], 'First table row lives on line 5');
});

test('testSecondTableCheckboxReportsItsOwnRow', async () => {
    const { harness, posted } = await renderWithHandler(TABLE_DOC);
    const boxes = checkboxes(harness);

    clickCheckbox(harness, boxes[1]);
    assertDeepEqual(posted, [{ line: 6, checked: false }], 'Second table row lives on line 6');
});

// === Non-checkbox clicks ===

test('testClickOnSurroundingTextPostsNothing', async () => {
    const { harness, posted } = await renderWithHandler(LIST_DOC);
    const heading = harness.document.querySelector('h1');

    heading.dispatchEvent(new harness.window.MouseEvent('click', { bubbles: true, cancelable: true }));

    assertEqual(posted.length, 0, 'Clicking a heading must not post a checkbox toggle');
});

// Summary
runAll().then(function() {
    console.log(`\n${passed} passed, ${failed} failed\n`);
    process.exit(failed > 0 ? 1 : 0);
});
