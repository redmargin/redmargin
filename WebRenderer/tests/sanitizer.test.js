/**
 * Tests for HTML sanitizer.
 * Run with: node WebRenderer/tests/sanitizer.test.js
 */

// Mock DOMParser for Node.js environment
const { JSDOM } = require('jsdom');
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.DOMParser = dom.window.DOMParser;
global.Node = dom.window.Node;

// Load sanitizer
const { sanitize, isSafeUrl } = require('../src/sanitizer.js');

// Test utilities
let passed = 0;
let failed = 0;

function test(name, fn) {
    try {
        fn();
        console.log(`\u2713 ${name}`);
        passed++;
    } catch (err) {
        console.log(`\u2717 ${name}`);
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

function assertNotContains(str, substr, msg = '') {
    if (str.includes(substr)) {
        throw new Error(`${msg}\n  Expected NOT to contain: ${substr}\n  Actual: ${str}`);
    }
}

function assertMatch(str, regex, msg = '') {
    if (!regex.test(str)) {
        throw new Error(`${msg}\n  Expected to match: ${regex}\n  Actual: ${str}`);
    }
}

function assertNotMatch(str, regex, msg = '') {
    if (regex.test(str)) {
        throw new Error(`${msg}\n  Expected NOT to match: ${regex}\n  Actual: ${str}`);
    }
}

// Tests
console.log('\nRunning sanitizer tests...\n');

// === Script tag removal ===
test('testSanitizesScriptTag', () => {
    const input = '<p>Hello</p><script>alert("xss")</script><p>World</p>';
    const output = sanitize(input);
    assertNotContains(output, '<script', 'Script tag should be removed');
    assertNotContains(output, 'alert', 'Script content should be removed');
    assertContains(output, '<p>Hello</p>', 'Safe content should be preserved');
    assertContains(output, '<p>World</p>', 'Safe content after script should be preserved');
});

test('testSanitizesScriptTagVariations', () => {
    const inputs = [
        '<script>alert(1)</script>',
        '<SCRIPT>alert(1)</SCRIPT>',
        '<script src="evil.js"></script>',
        '<script type="text/javascript">alert(1)</script>'
    ];
    for (const input of inputs) {
        const output = sanitize(input);
        assertNotContains(output.toLowerCase(), '<script', `Script variation should be removed: ${input}`);
    }
});

// === Event handler removal ===
test('testSanitizesEventHandler', () => {
    const input = '<img src="x" onerror="alert(1)">';
    const output = sanitize(input);
    assertNotContains(output, 'onerror', 'onerror handler should be removed');
    assertContains(output, '<img', 'img tag should be preserved');
});

test('testSanitizesAllEventHandlers', () => {
    const handlers = ['onclick', 'onload', 'onerror', 'onmouseover', 'onfocus', 'onblur'];
    for (const handler of handlers) {
        const input = `<p ${handler}="alert(1)">text</p>`;
        const output = sanitize(input);
        assertNotContains(output, handler, `${handler} should be removed`);
        assertContains(output, '<p', 'Element should be preserved');
    }
});

// === JavaScript URL removal ===
test('testSanitizesJavascriptUrl', () => {
    const input = '<a href="javascript:alert(1)">click me</a>';
    const output = sanitize(input);
    assertNotContains(output, 'javascript:', 'javascript: URL should be removed');
    assertContains(output, '<a', 'Anchor tag should be preserved');
    assertContains(output, 'click me', 'Link text should be preserved');
});

test('testSanitizesJavascriptUrlVariations', () => {
    const inputs = [
        '<a href="javascript:alert(1)">link</a>',
        '<a href="JAVASCRIPT:alert(1)">link</a>',
        '<a href="  javascript:alert(1)">link</a>',
        '<a href="vbscript:msgbox(1)">link</a>'
    ];
    for (const input of inputs) {
        const output = sanitize(input);
        assertNotMatch(output, /href\s*=\s*["'](javascript|vbscript):/i, `Dangerous URL should be removed: ${input}`);
    }
});

// === Safe HTML preservation ===
test('testAllowsSafeHtml', () => {
    const input = '<p><strong>bold</strong> and <em>italic</em></p>';
    const output = sanitize(input);
    assertContains(output, '<p>', 'p tag should be preserved');
    assertContains(output, '<strong>', 'strong tag should be preserved');
    assertContains(output, '<em>', 'em tag should be preserved');
    assertContains(output, 'bold', 'Content should be preserved');
});

test('testAllowsHeadings', () => {
    for (let i = 1; i <= 6; i++) {
        const input = `<h${i}>Heading ${i}</h${i}>`;
        const output = sanitize(input);
        assertContains(output, `<h${i}>`, `h${i} should be preserved`);
    }
});

test('testAllowsLists', () => {
    const input = '<ul><li>Item 1</li><li>Item 2</li></ul>';
    const output = sanitize(input);
    assertContains(output, '<ul>', 'ul should be preserved');
    assertContains(output, '<li>', 'li should be preserved');
});

test('testAllowsBlockquote', () => {
    const input = '<blockquote>Quote text</blockquote>';
    const output = sanitize(input);
    assertContains(output, '<blockquote>', 'blockquote should be preserved');
});

test('testAllowsCodeBlocks', () => {
    const input = '<pre><code>const x = 1;</code></pre>';
    const output = sanitize(input);
    assertContains(output, '<pre>', 'pre should be preserved');
    assertContains(output, '<code>', 'code should be preserved');
});

// === Table preservation ===
test('testAllowsTable', () => {
    const input = '<table><thead><tr><th>Header</th></tr></thead><tbody><tr><td>Cell</td></tr></tbody></table>';
    const output = sanitize(input);
    assertContains(output, '<table>', 'table should be preserved');
    assertContains(output, '<thead>', 'thead should be preserved');
    assertContains(output, '<tbody>', 'tbody should be preserved');
    assertContains(output, '<tr>', 'tr should be preserved');
    assertContains(output, '<th>', 'th should be preserved');
    assertContains(output, '<td>', 'td should be preserved');
});

// === Checkbox preservation ===
test('testAllowsCheckbox', () => {
    const input = '<input type="checkbox" checked disabled>';
    const output = sanitize(input);
    assertContains(output, '<input', 'input should be preserved');
    assertContains(output, 'type="checkbox"', 'type attribute should be preserved');
    assertContains(output, 'checked', 'checked attribute should be preserved');
    assertContains(output, 'disabled', 'disabled attribute should be preserved');
});

test('testRemovesNonCheckboxInput', () => {
    const inputs = [
        '<input type="text" value="test">',
        '<input type="password">',
        '<input type="submit">',
        '<input type="hidden" value="secret">'
    ];
    for (const input of inputs) {
        const output = sanitize(input);
        assertNotContains(output, '<input', `Non-checkbox input should be removed: ${input}`);
    }
});

// === data-sourcepos preservation ===
test('testPreservesSourcepos', () => {
    const input = '<p data-sourcepos="1:0-1:10">text</p>';
    const output = sanitize(input);
    assertContains(output, 'data-sourcepos="1:0-1:10"', 'data-sourcepos should be preserved');
});

// === Unknown attribute removal ===
test('testRemovesUnknownAttributes', () => {
    const input = '<p data-evil="malicious" data-sourcepos="1:0-1:0">text</p>';
    const output = sanitize(input);
    assertNotContains(output, 'data-evil', 'Unknown data attribute should be removed');
    assertContains(output, 'data-sourcepos', 'data-sourcepos should be preserved');
});

test('testRemovesStyleAttribute', () => {
    const input = '<p style="color: red;">text</p>';
    const output = sanitize(input);
    assertNotContains(output, 'style=', 'style attribute should be removed');
});

// === Image handling ===
test('testAllowsImageWithSafeAttributes', () => {
    const input = '<img src="image.png" alt="description" title="tooltip">';
    const output = sanitize(input);
    assertContains(output, '<img', 'img should be preserved');
    assertContains(output, 'src="image.png"', 'src should be preserved');
    assertContains(output, 'alt="description"', 'alt should be preserved');
});

test('testRemovesImageOnError', () => {
    const input = '<img src="x" onerror="alert(1)" alt="test">';
    const output = sanitize(input);
    assertNotContains(output, 'onerror', 'onerror should be removed from img');
    assertContains(output, 'src="x"', 'src should be preserved');
});

// === Link handling ===
test('testAllowsValidLinks', () => {
    const input = '<a href="https://example.com" title="Example">Link</a>';
    const output = sanitize(input);
    assertContains(output, 'href="https://example.com"', 'https href should be preserved');
    assertContains(output, 'title="Example"', 'title should be preserved');
});

test('testAllowsRelativeLinks', () => {
    const input = '<a href="./page.html">Link</a>';
    const output = sanitize(input);
    assertContains(output, 'href="./page.html"', 'Relative href should be preserved');
});

// === Dangerous tags removal ===
test('testRemovesDangerousTags', () => {
    const dangerousTags = ['iframe', 'object', 'embed', 'form', 'style', 'meta', 'link', 'base'];
    for (const tag of dangerousTags) {
        const input = `<${tag}>content</${tag}>`;
        const output = sanitize(input);
        assertNotContains(output.toLowerCase(), `<${tag}`, `${tag} should be removed`);
    }
});

// === Unknown tags handling (unwrap) ===
test('testUnwrapsUnknownTags', () => {
    const input = '<custom-element>content inside</custom-element>';
    const output = sanitize(input);
    assertNotContains(output, '<custom-element', 'Custom element should be removed');
    assertContains(output, 'content inside', 'Content should be preserved');
});

// === Data URL handling ===
test('testAllowsSafeImageDataUrls', () => {
    const input = '<img src="data:image/png;base64,abc123">';
    const output = sanitize(input);
    assertContains(output, 'data:image/png', 'Safe image data URL should be preserved');
});

test('testBlocksDangerousDataUrls', () => {
    const input = '<a href="data:text/html,<script>alert(1)</script>">link</a>';
    const output = sanitize(input);
    assertNotMatch(output, /href\s*=\s*["']data:/, 'Dangerous data URL should be removed from href');
});

// === ID and class preservation ===
test('testPreservesIdAndClass', () => {
    const input = '<p id="intro" class="highlight">text</p>';
    const output = sanitize(input);
    assertContains(output, 'id="intro"', 'id should be preserved');
    assertContains(output, 'class="highlight"', 'class should be preserved');
});

// === Edge cases ===
test('testHandlesEmptyInput', () => {
    assertEqual(sanitize(''), '', 'Empty string should return empty');
    assertEqual(sanitize(null), '', 'null should return empty');
    assertEqual(sanitize(undefined), '', 'undefined should return empty');
});

test('testHandlesPlainText', () => {
    const input = 'Just plain text with no HTML';
    const output = sanitize(input);
    assertContains(output, 'Just plain text', 'Plain text should be preserved');
});

test('testHandlesNestedMaliciousContent', () => {
    const input = '<p><span onclick="alert(1)"><strong>nested <script>alert(2)</script> content</strong></span></p>';
    const output = sanitize(input);
    assertNotContains(output, 'onclick', 'Nested onclick should be removed');
    assertNotContains(output, '<script', 'Nested script should be removed');
    assertContains(output, '<strong>', 'strong should be preserved');
    assertContains(output, 'nested', 'Content should be preserved');
});

// === isSafeUrl function tests ===
test('testIsSafeUrlValidUrls', () => {
    assertEqual(isSafeUrl('https://example.com'), true, 'https should be safe');
    assertEqual(isSafeUrl('http://example.com'), true, 'http should be safe');
    assertEqual(isSafeUrl('./relative.html'), true, 'Relative should be safe');
    assertEqual(isSafeUrl('/absolute/path'), true, 'Absolute path should be safe');
    assertEqual(isSafeUrl('#anchor'), true, 'Anchor should be safe');
});

test('testIsSafeUrlDangerousUrls', () => {
    assertEqual(isSafeUrl('javascript:alert(1)'), false, 'javascript: should be unsafe');
    assertEqual(isSafeUrl('JAVASCRIPT:alert(1)'), false, 'JAVASCRIPT: should be unsafe');
    assertEqual(isSafeUrl('vbscript:msgbox(1)'), false, 'vbscript: should be unsafe');
    // data: URLs are handled separately by isSafeDataUrl
    assertEqual(isSafeUrl('data:text/html,<script>'), true, 'data: passes isSafeUrl (checked separately)');
});

// Summary
console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
