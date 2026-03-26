/**
 * Tests for Mermaid renderer integration.
 * Run with: node WebRenderer/tests/mermaid.test.js
 */

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
        throw new Error(msg || 'Expected value to be truthy');
    }
}

function assertFalse(value, msg = '') {
    if (value) {
        throw new Error(msg || 'Expected value to be falsy');
    }
}

function assertContains(str, substr, msg = '') {
    if (!str.includes(substr)) {
        throw new Error(`${msg}\n  Expected to contain: ${substr}\n  Actual: ${str}`);
    }
}

function createStubMermaid() {
    let theme = 'default';
    return {
        initialize(config) {
            theme = config.theme;
        },
        async render(id, source) {
            if (source.includes('INVALID')) {
                throw new Error('Parse error on line 1');
            }

            const fill = theme === 'dark' ? '#f8fafc' : '#111827';
            const stroke = theme === 'dark' ? '#94a3b8' : '#475569';
            return {
                svg: `<svg id="${id}" onclick="alert('x')" data-theme="${theme}"><g fill="${fill}" stroke="${stroke}"></g></svg>`
            };
        }
    };
}

async function renderMarkdown(harness, markdown, theme = 'light') {
    harness.window.App.render({
        markdown,
        options: {
            theme,
            basePath: ''
        }
    });
    await flushPromises();
    await flushPromises();
}

console.log('\nRunning Mermaid tests...\n');

async function run() {
    await test('testMermaidFenceRendersSvg', async () => {
        const harness = createAppHarness({
            createMermaid: createStubMermaid
        });

        await renderMarkdown(harness, '```mermaid\ngraph TD\n  A-->B\n```');

        const block = harness.document.querySelector('.mermaid-block');
        const svg = block && block.querySelector('svg');
        assertTrue(!!block, 'Expected Mermaid block to be rendered');
        assertTrue(!!svg, 'Expected Mermaid block to contain an SVG');
        assertEqual(svg.getAttribute('onclick'), null, 'Sanitizer should remove SVG event handlers');
    });

    await test('testMermaidFenceFallsBackToSourceOnRenderError', async () => {
        const harness = createAppHarness({
            createMermaid: createStubMermaid
        });

        await renderMarkdown(harness, '```mermaid\ngraph INVALID\n```');

        const block = harness.document.querySelector('.mermaid-block');
        const error = block && block.querySelector('.mermaid-error');
        const code = block && block.querySelector('pre code');

        assertTrue(!!error, 'Expected invalid Mermaid to show an error banner');
        assertContains(error.textContent, 'Parse error', 'Expected Mermaid error text to be shown');
        assertEqual(code.textContent, 'graph INVALID\n', 'Expected original Mermaid source fallback');
    });

    await test('testMermaidThemeRerenderUpdatesExistingBlocks', async () => {
        const harness = createAppHarness({
            createMermaid: createStubMermaid
        });
        const markdown = '```mermaid\ngraph TD\n  A-->B\n```';

        await renderMarkdown(harness, markdown, 'light');
        const initialFill = harness.document.querySelector('.mermaid-block svg g').getAttribute('fill');

        await renderMarkdown(harness, markdown, 'dark');
        const rerenderedFill = harness.document.querySelector('.mermaid-block svg g').getAttribute('fill');

        assertFalse(initialFill === rerenderedFill, 'Expected Mermaid rerender to update SVG colors');
    });

    await test('testMermaidCopySourceUsesOriginalFenceText', async () => {
        const harness = createAppHarness({
            createMermaid: createStubMermaid
        });
        const markdown = '```mermaid\ngraph TD\n  A-->B\n```';
        const expectedSource = 'graph TD\n  A-->B\n';

        await renderMarkdown(harness, markdown);

        const block = harness.document.querySelector('.mermaid-block');
        const button = block && block.querySelector('.copy-btn');

        assertEqual(block.getAttribute('data-source'), expectedSource, 'Expected block to preserve original source text');
        button.click();
        await flushPromises();

        assertEqual(harness.getClipboardText(), expectedSource, 'Expected copy button to write original Mermaid source');
    });

    await test('testMermaidGracefulDegradationWhenMermaidUnavailable', async () => {
        const harness = createAppHarness({
            disableMermaid: true
        });

        await renderMarkdown(harness, '```mermaid\ngraph TD\n  A-->B\n```');

        const block = harness.document.querySelector('.mermaid-block');
        const code = block && block.querySelector('pre code');

        assertTrue(!!code, 'Expected Mermaid block to fall back to plain code');
        assertEqual(block.querySelector('.mermaid-error'), null, 'Expected no Mermaid error banner when library is unavailable');
        assertEqual(code.textContent, 'graph TD\n  A-->B\n', 'Expected original Mermaid source in code fallback');
    });

    console.log(`\n${passed} passed, ${failed} failed\n`);
    process.exit(failed > 0 ? 1 : 0);
}

run();
