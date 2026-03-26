const { JSDOM } = require('jsdom');
const markdownit = require('markdown-it');
const taskLists = require('markdown-it-task-lists');

const sourceposPlugin = require('../src/sourcepos.js');
const headingAnchorsPlugin = require('../src/headingAnchors.js');
const tableCheckboxPlugin = require('../src/tableCheckboxPlugin.js');
const sanitizer = require('../src/sanitizer.js');

async function flushPromises(times = 4) {
    for (let i = 0; i < times; i++) {
        await Promise.resolve();
    }
}

function createAppHarness(options = {}) {
    const dom = new JSDOM(
        '<!DOCTYPE html><html><body>' +
        '<div id="gutter-container"><div id="git-gutter"></div><div id="line-numbers-container"></div></div>' +
        '<div id="content-container"></div>' +
        '</body></html>',
        {
            pretendToBeVisual: true,
            runScripts: 'outside-only',
            url: 'https://example.com'
        }
    );

    const { window } = dom;
    let clipboardText = null;
    const lineNumberCalls = [];
    const gutterCalls = [];

    global.window = window;
    global.document = window.document;
    global.DOMParser = window.DOMParser;
    global.Node = window.Node;
    global.XMLSerializer = window.XMLSerializer;
    global.navigator = window.navigator;

    window.requestAnimationFrame = function(callback) {
        callback();
        return 1;
    };
    window.cancelAnimationFrame = function() {};
    global.requestAnimationFrame = window.requestAnimationFrame;
    global.cancelAnimationFrame = window.cancelAnimationFrame;
    window.scrollTo = function() {};
    window.markdownit = markdownit;
    window.markdownitTaskLists = taskLists;
    window.sourceposPlugin = sourceposPlugin;
    window.headingAnchorsPlugin = headingAnchorsPlugin;
    window.tableCheckboxPlugin = tableCheckboxPlugin;
    window.Sanitizer = {
        sanitize: sanitizer.sanitize,
        sanitizeMermaidSvg: sanitizer.sanitizeMermaidSvg
    };
    window.LineNumbers = {
        generate: function() {
            lineNumberCalls.push(true);
        },
        setVisible: function() {}
    };
    window.Gutter = {
        update: function(changes) {
            gutterCalls.push(changes || null);
        }
    };
    window.ScrollPosition = {
        restore: function() {}
    };
    window.highlightCode = function() {
        return '';
    };
    Object.defineProperty(window.navigator, 'clipboard', {
        configurable: true,
        value: {
            writeText: async function(text) {
                clipboardText = text;
            }
        }
    });

    if (options.disableMermaid) {
        delete window.mermaid;
    } else if (typeof options.createMermaid === 'function') {
        window.mermaid = options.createMermaid(window);
    }

    delete require.cache[require.resolve('../src/sourcepos-map.js')];
    delete require.cache[require.resolve('../src/mermaid.js')];
    delete require.cache[require.resolve('../src/frontMatter.js')];
    delete require.cache[require.resolve('../src/index.js')];
    require('../src/sourcepos-map.js');
    require('../src/mermaid.js');
    require('../src/frontMatter.js');
    require('../src/index.js');

    return {
        dom,
        window,
        document: window.document,
        lineNumberCalls,
        gutterCalls,
        getClipboardText: function() {
            return clipboardText;
        }
    };
}

module.exports = {
    createAppHarness,
    flushPromises
};
