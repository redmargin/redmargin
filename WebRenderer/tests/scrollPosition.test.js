/**
 * Tests for the scroll position manager.
 * Run with: node WebRenderer/tests/scrollPosition.test.js
 *
 * The reader's scroll offset survives a re-render only because this module saves
 * it and puts it back, so the assertions are about what it saves and what it restores.
 */

const { JSDOM } = require('jsdom');

// Test utilities
let passed = 0;
let failed = 0;

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

console.log('\nRunning scroll position tests...\n');

/** Fresh module instance bound to a fresh window, with the Swift bridge captured. */
function createScrollHarness() {
    const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', { pretendToBeVisual: true });
    const { window } = dom;

    const posted = [];
    const scrollToCalls = [];
    let currentScrollY = 0;

    Object.defineProperty(window, 'scrollY', {
        configurable: true,
        get: function() { return currentScrollY; }
    });
    window.scrollTo = function(x, y) {
        scrollToCalls.push({ x, y });
        currentScrollY = y;
    };
    window.webkit = {
        messageHandlers: {
            scrollPosition: {
                postMessage: function(message) { posted.push(message); }
            }
        }
    };

    global.window = window;
    global.document = window.document;

    delete require.cache[require.resolve('../src/scrollPosition.js')];
    require('../src/scrollPosition.js');

    // The module defers its scroll listener until the document is ready, exactly as
    // it does in the app. A fresh jsdom is still 'loading', so drive that lifecycle.
    if (window.document.readyState === 'loading') {
        window.document.dispatchEvent(new window.Event('DOMContentLoaded'));
    }

    return {
        window,
        posted,
        scrollToCalls,
        setScrollY: function(value) { currentScrollY = value; }
    };
}

function wait(ms) {
    return new Promise(function(resolve) { setTimeout(resolve, ms); });
}

// === Restore ===

test('testRestorePutsTheReaderBackWhereTheyWere', async () => {
    const h = createScrollHarness();

    h.window.ScrollPosition.restore(420);
    await wait(80);

    assertDeepEqual(h.scrollToCalls, [{ x: 0, y: 420 }], 'Restore should scroll to the saved offset');
});

test('testRestoreIgnoresNonNumericOffset', async () => {
    const h = createScrollHarness();

    h.window.ScrollPosition.restore('420');
    h.window.ScrollPosition.restore(null);
    h.window.ScrollPosition.restore(undefined);
    await wait(80);

    assertEqual(h.scrollToCalls.length, 0, 'A non-numeric offset must not move the reader');
});

test('testRestoreIgnoresNegativeOffset', async () => {
    const h = createScrollHarness();

    h.window.ScrollPosition.restore(-1);
    await wait(80);

    assertEqual(h.scrollToCalls.length, 0, 'A negative offset must not move the reader');
});

test('testRestoreToTopIsHonoured', async () => {
    const h = createScrollHarness();
    h.setScrollY(500);

    h.window.ScrollPosition.restore(0);
    await wait(80);

    assertDeepEqual(h.scrollToCalls, [{ x: 0, y: 0 }], 'Zero is a real offset, not a missing one');
});

// === Save ===

test('testSaveReportsTheCurrentOffsetToSwift', async () => {
    const h = createScrollHarness();
    h.setScrollY(310);

    h.window.ScrollPosition.save();

    assertDeepEqual(h.posted, [{ scrollY: 310 }], 'Save should post the current offset');
});

test('testSaveDoesNotRepostAnUnchangedOffset', async () => {
    const h = createScrollHarness();
    h.setScrollY(310);

    h.window.ScrollPosition.save();
    h.window.ScrollPosition.save();

    assertDeepEqual(h.posted, [{ scrollY: 310 }], 'An unchanged offset should be posted once');
});

test('testSaveAfterRestoreDoesNotEchoTheRestoredOffset', async () => {
    const h = createScrollHarness();

    h.window.ScrollPosition.restore(250);
    await wait(80);
    h.window.ScrollPosition.save();

    assertEqual(h.posted.length, 0, 'Restoring a position must not post it straight back');
});

// === Scroll listener ===

test('testScrollingPostsTheOffsetOnceTheReaderSettles', async () => {
    const h = createScrollHarness();

    h.setScrollY(100);
    h.window.dispatchEvent(new h.window.Event('scroll'));
    h.setScrollY(200);
    h.window.dispatchEvent(new h.window.Event('scroll'));

    assertEqual(h.posted.length, 0, 'Nothing is posted while the reader is still scrolling');

    await wait(260);
    assertDeepEqual(h.posted, [{ scrollY: 200 }], 'The settled offset is posted once, not once per event');
});

// Summary
runAll().then(function() {
    console.log(`\n${passed} passed, ${failed} failed\n`);
    process.exit(failed > 0 ? 1 : 0);
});
