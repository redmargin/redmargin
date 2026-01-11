/**
 * Line Numbers for RedMargin
 * Generates line number elements in gutter based on data-sourcepos attributes.
 * Shows ALL lines including blank lines between elements.
 */
(function() {
    'use strict';

    // Collect line positions from elements, then fill gaps
    var linePositions = {}; // lineNum -> top position

    function recordLine(lineNum, top) {
        linePositions[lineNum] = top;
    }

    function collectTableLines(el, startLine, gutterTop) {
        const rows = el.querySelectorAll('tr');
        let sourceLine = startLine;
        // Table rows have internal padding, need extra offset
        const tableRowOffset = 8;

        rows.forEach(function(row, idx) {
            const rowRect = row.getBoundingClientRect();

            if (idx === 0) {
                recordLine(sourceLine, rowRect.top - gutterTop + tableRowOffset);
                const separatorTop = rowRect.top + (rowRect.height / 2) - gutterTop + tableRowOffset;
                recordLine(sourceLine + 1, separatorTop);
                sourceLine += 2;
            } else {
                recordLine(sourceLine, rowRect.top - gutterTop + tableRowOffset);
                sourceLine += 1;
            }
        });
    }

    function collectCodeBlockLines(el, startLine, endLine, gutterTop) {
        const rect = el.getBoundingClientRect();
        const elementTop = rect.top - gutterTop;
        const lineCount = endLine - startLine + 1;
        const lineHeight = rect.height / lineCount;

        for (let i = 0; i < lineCount; i++) {
            recordLine(startLine + i, elementTop + (i * lineHeight));
        }
    }

    function collectListLines(el, startLine, gutterTop) {
        const items = el.querySelectorAll(':scope > li');
        let sourceLine = startLine;

        items.forEach(function(item) {
            const itemRect = item.getBoundingClientRect();
            recordLine(sourceLine, itemRect.top - gutterTop);
            sourceLine += 1;
        });
    }

    function fillGaps() {
        // Get all recorded line numbers sorted
        const lines = Object.keys(linePositions).map(Number).sort(function(a, b) {
            return a - b;
        });

        if (lines.length < 2) return;

        // Fill gaps between consecutive recorded lines
        for (let i = 0; i < lines.length - 1; i++) {
            const currLine = lines[i];
            const nextLine = lines[i + 1];
            const currTop = linePositions[currLine];
            const nextTop = linePositions[nextLine];

            // If there's a gap, interpolate
            const gap = nextLine - currLine;
            if (gap > 1) {
                const heightPerLine = (nextTop - currTop) / gap;
                for (let j = 1; j < gap; j++) {
                    const missingLine = currLine + j;
                    linePositions[missingLine] = currTop + (j * heightPerLine);
                }
            }
        }
    }

    function renderLineNumbers(container) {
        const lines = Object.keys(linePositions).map(Number).sort(function(a, b) {
            return a - b;
        });

        // Offset to align line numbers with text baseline
        const verticalOffset = 3;

        lines.forEach(function(lineNum) {
            const lineEl = document.createElement('div');
            lineEl.className = 'line-number';
            lineEl.textContent = lineNum;
            lineEl.style.top = (linePositions[lineNum] + verticalOffset) + 'px';
            container.appendChild(lineEl);
        });
    }

    function generateLineNumbers() {
        const container = document.getElementById('line-numbers-container');
        const gutter = document.getElementById('gutter-container');
        const content = document.getElementById('content-container');

        if (!container || !gutter || !content) return;

        container.innerHTML = '';
        linePositions = {};

        const elements = content.querySelectorAll('[data-sourcepos]');
        if (elements.length === 0) return;

        const gutterRect = gutter.getBoundingClientRect();

        // Pass 1: Collect line positions from all elements
        elements.forEach(function(el) {
            const sourcepos = el.getAttribute('data-sourcepos');
            if (!sourcepos) return;

            const match = sourcepos.match(/^(\d+):\d+-(\d+):\d+$/);
            if (!match) return;

            const startLine = parseInt(match[1], 10);
            const endLine = parseInt(match[2], 10);
            const tagName = el.tagName.toLowerCase();

            if (tagName === 'table') {
                collectTableLines(el, startLine, gutterRect.top);
            } else if (tagName === 'pre') {
                collectCodeBlockLines(el, startLine, endLine, gutterRect.top);
            } else if (tagName === 'ul' || tagName === 'ol') {
                collectListLines(el, startLine, gutterRect.top);
            } else {
                const rect = el.getBoundingClientRect();
                recordLine(startLine, rect.top - gutterRect.top);
            }
        });

        // Pass 2: Fill in gaps (blank lines between elements)
        fillGaps();

        // Pass 3: Render all line numbers
        renderLineNumbers(container);
    }

    function setVisible(visible) {
        const container = document.getElementById('line-numbers-container');
        if (!container) return;

        window.LineNumbers._enabled = visible;

        if (visible) {
            container.style.display = '';
            generateLineNumbers();
        } else {
            container.style.display = 'none';
        }
    }

    // Export for use by App.render
    window.LineNumbers = {
        generate: generateLineNumbers,
        setVisible: setVisible
    };

    // Re-generate on window resize
    window.addEventListener('resize', function() {
        if (window.LineNumbers._enabled) {
            generateLineNumbers();
        }
    });

    window.LineNumbers._enabled = true;
})();
