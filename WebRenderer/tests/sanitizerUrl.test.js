/**
 * Tests for sanitizer URL handling: scheme extraction and the href/src allowlists.
 * Run with: node WebRenderer/tests/sanitizerUrl.test.js
 */

// Mock DOMParser for Node.js environment
const { JSDOM } = require('jsdom');
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.DOMParser = dom.window.DOMParser;
global.Node = dom.window.Node;
global.XMLSerializer = dom.window.XMLSerializer;

// Load sanitizer
const { sanitize, isSafeHref, isSafeSrc, getUrlScheme } = require('../src/sanitizer.js');

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

console.log('\nRunning sanitizer URL tests...\n');

// === URL scheme extraction tests ===
test('testGetUrlScheme', () => {
    assertEqual(getUrlScheme('https://example.com'), 'https:', 'Should extract https:');
    assertEqual(getUrlScheme('http://example.com'), 'http:', 'Should extract http:');
    assertEqual(getUrlScheme('mailto:test@example.com'), 'mailto:', 'Should extract mailto:');
    assertEqual(getUrlScheme('file:///path/to/file'), 'file:', 'Should extract file:');
    assertEqual(getUrlScheme('javascript:alert(1)'), 'javascript:', 'Should extract javascript:');
    assertEqual(getUrlScheme('ftp://server.com'), 'ftp:', 'Should extract ftp:');
});

test('testGetUrlSchemeRelativeUrls', () => {
    assertEqual(getUrlScheme('./relative.html'), null, 'Relative ./ should return null');
    assertEqual(getUrlScheme('../parent.html'), null, 'Relative ../ should return null');
    assertEqual(getUrlScheme('/absolute/path'), null, 'Absolute path should return null');
    assertEqual(getUrlScheme('#anchor'), null, 'Anchor should return null');
    assertEqual(getUrlScheme('?query=1'), null, 'Query should return null');
    assertEqual(getUrlScheme('page.html'), null, 'Simple filename should return null');
});

// Browsers delete tab, LF, and CR from a URL and skip leading C0 controls before
// reading the scheme, so the sanitizer has to read it the same way. Padding the
// scheme past any fixed length budget must not turn it into a relative URL.
test('testGetUrlSchemeIgnoresStrippedCharacters', () => {
    assertEqual(getUrlScheme('java\t\tscript:alert(1)'), 'javascript:', 'Tabs inside the scheme are stripped');
    assertEqual(getUrlScheme('java\n\n\nscript:alert(1)'), 'javascript:', 'Newlines inside the scheme are stripped');
    assertEqual(getUrlScheme('ja\tva\nscr\ript:alert(1)'), 'javascript:', 'Mixed tab/LF/CR is stripped');
    assertEqual(getUrlScheme('\x01javascript:alert(1)'), 'javascript:', 'Leading C0 control is skipped');
    assertEqual(getUrlScheme('  \tjavascript:alert(1)'), 'javascript:', 'Leading whitespace is skipped');
});

test('testIsSafeHrefRejectsObfuscatedSchemes', () => {
    assertEqual(isSafeHref('java\t\tscript:alert(1)'), false, 'Tab-padded javascript: must be blocked');
    assertEqual(isSafeHref('java\n\n\nscript:alert(1)'), false, 'Newline-padded javascript: must be blocked');
    assertEqual(isSafeHref('\x01javascript:alert(1)'), false, 'Control-prefixed javascript: must be blocked');
});

test('testSanitizesSchemesPaddedPastTheLengthBudget', () => {
    // Each of these is longer than 'javascript:' before the colon, which an
    // index-based scheme cap reads as a relative URL and lets through.
    const inputs = [
        '<a href="java&#9;&#9;script:alert(1)">link</a>',
        '<a href="java&#10;&#10;&#10;script:alert(1)">link</a>',
        '<a href="ja&#9;va&#10;scr&#13;ipt:alert(1)">link</a>',
        '<a href="&#10;java&#9;&#9;script:alert(1)">link</a>'
    ];
    for (const input of inputs) {
        const output = sanitize(input);
        assertNotMatch(output, /href\s*=/i, `Obfuscated scheme should lose its href: ${JSON.stringify(input)}`);
        assertContains(output, 'link', 'Link text should be preserved');
    }
});

test('testSanitizesObfuscatedDataUrlOnImage', () => {
    const output = sanitize('<img src="da&#9;&#9;ta:text/html,evil">');
    assertNotMatch(output, /src\s*=/i, 'Tab-padded data: URL should lose its src');
});

// === isSafeHref function tests (explicit allowlist) ===
test('testIsSafeHrefAllowedSchemes', () => {
    assertEqual(isSafeHref('https://example.com'), true, 'https should be safe for href');
    assertEqual(isSafeHref('http://example.com'), true, 'http should be safe for href');
    assertEqual(isSafeHref('mailto:test@example.com'), true, 'mailto should be safe for href');
});

test('testIsSafeHrefRelativeUrls', () => {
    assertEqual(isSafeHref('./relative.html'), true, 'Relative ./ should be safe');
    assertEqual(isSafeHref('../parent.html'), true, 'Relative ../ should be safe');
    assertEqual(isSafeHref('/absolute/path'), true, 'Absolute path should be safe');
    assertEqual(isSafeHref('#anchor'), true, 'Anchor should be safe');
    assertEqual(isSafeHref('page.html'), true, 'Simple filename should be safe');
});

test('testIsSafeHrefBlockedSchemes', () => {
    assertEqual(isSafeHref('javascript:alert(1)'), false, 'javascript: should be blocked');
    assertEqual(isSafeHref('JAVASCRIPT:alert(1)'), false, 'JAVASCRIPT: should be blocked');
    assertEqual(isSafeHref('vbscript:msgbox(1)'), false, 'vbscript: should be blocked');
    assertEqual(isSafeHref('file:///etc/passwd'), false, 'file: should be blocked in href');
    assertEqual(isSafeHref('ftp://server.com/file'), false, 'ftp: should be blocked');
    assertEqual(isSafeHref('smb://server/share'), false, 'smb: should be blocked');
    assertEqual(isSafeHref('data:text/html,<script>'), false, 'data: should be blocked in href');
});

// === isSafeSrc function tests (explicit allowlist) ===
test('testIsSafeSrcAllowedSchemes', () => {
    assertEqual(isSafeSrc('https://example.com/img.png'), true, 'https should be safe for src');
    assertEqual(isSafeSrc('http://example.com/img.png'), true, 'http should be safe for src');
    assertEqual(isSafeSrc('file:///path/to/image.png'), true, 'file: should be safe for src');
});

test('testIsSafeSrcRelativeUrls', () => {
    assertEqual(isSafeSrc('./image.png'), true, 'Relative ./ should be safe');
    assertEqual(isSafeSrc('../images/photo.jpg'), true, 'Relative ../ should be safe');
    assertEqual(isSafeSrc('/absolute/path/img.gif'), true, 'Absolute path should be safe');
    assertEqual(isSafeSrc('image.png'), true, 'Simple filename should be safe');
});

test('testIsSafeSrcDataUrls', () => {
    // data: URLs are allowed through isSafeSrc but validated separately by isSafeDataUrl
    assertEqual(isSafeSrc('data:image/png;base64,abc'), true, 'data: should pass isSafeSrc (validated separately)');
});

test('testIsSafeSrcBlockedSchemes', () => {
    assertEqual(isSafeSrc('javascript:alert(1)'), false, 'javascript: should be blocked');
    assertEqual(isSafeSrc('ftp://server.com/img.png'), false, 'ftp: should be blocked');
    assertEqual(isSafeSrc('smb://server/share/img.png'), false, 'smb: should be blocked');
});

// === Integration: sanitize with scheme allowlist ===
test('testSanitizeBlocksFileHref', () => {
    const input = '<a href="file:///etc/passwd">local file</a>';
    const output = sanitize(input);
    assertNotMatch(output, /href\s*=/, 'file: href should be removed');
    assertContains(output, 'local file', 'Link text should be preserved');
});

test('testSanitizeAllowsFileSrc', () => {
    const input = '<img src="file:///path/to/image.png" alt="local">';
    const output = sanitize(input);
    assertContains(output, 'file:///path/to/image.png', 'file: src should be preserved');
});

test('testSanitizeBlocksFtpHref', () => {
    const input = '<a href="ftp://server.com/file">ftp link</a>';
    const output = sanitize(input);
    assertNotMatch(output, /href\s*=/, 'ftp: href should be removed');
});

test('testSanitizeBlocksSmbHref', () => {
    const input = '<a href="smb://server/share">network share</a>';
    const output = sanitize(input);
    assertNotMatch(output, /href\s*=/, 'smb: href should be removed');
});
// Summary
console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
