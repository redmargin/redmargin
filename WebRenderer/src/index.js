/**
 * RedMargin Markdown Renderer
 * Renders Markdown to HTML with sourcepos attributes for Git gutter integration.
 */
(function() {
    'use strict';

    const md = window.markdownit({
        html: true,
        linkify: true,
        typographer: false,
        breaks: false,
        highlight: function(code, lang) {
            if (window.highlightCode) {
                return window.highlightCode(code, lang);
            }
            return '';
        }
    });

    md.use(window.markdownitTaskLists, { enabled: true, label: true });
    md.use(window.tableCheckboxPlugin);
    md.use(window.sourceposPlugin);
    md.use(window.headingAnchorsPlugin);

    let currentTheme = 'light';
    let currentBasePath = '';
    let lastRenderedMarkdown = null;
    let latestChanges = null;  // Always use latest changes for gutter
    let lastFrontMatterOffset = 0;  // Line offset from stripped front matter

    // --- Front Matter ---

    /**
     * Extracts YAML front matter from markdown string.
     * Returns { body, fields, lineCount } where lineCount includes both --- delimiters.
     */
    function extractFrontMatter(markdown) {
        if (!markdown || !markdown.startsWith('---')) {
            return { body: markdown, fields: null, lineCount: 0 };
        }

        // Match opening --- followed by content, then closing ---
        var match = markdown.match(/^---[ \t]*\n([\s\S]*?)\n---[ \t]*(?:\n|$)/);
        if (!match) {
            return { body: markdown, fields: null, lineCount: 0 };
        }

        var yamlBlock = match[1];
        var fullMatch = match[0];
        var body = markdown.slice(fullMatch.length);
        var lineCount = fullMatch.split('\n').length - (fullMatch.endsWith('\n') ? 1 : 0);

        var fields = parseYamlSubset(yamlBlock);
        if (!fields || fields.length === 0) {
            return { body: markdown, fields: null, lineCount: 0 };
        }

        return { body: body, fields: fields, lineCount: lineCount };
    }

    /**
     * Micro YAML parser for front matter subset:
     * scalar values, simple arrays (both flow [a, b] and block - item).
     */
    function parseYamlSubset(yaml) {
        var lines = yaml.split('\n');
        var fields = [];
        var currentKey = null;
        var currentArrayItems = null;

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];

            // Skip empty lines and comments
            if (/^\s*$/.test(line) || /^\s*#/.test(line)) continue;

            // Check for block array item (continuation of previous key)
            var arrayItemMatch = line.match(/^\s+-\s+(.*)/);
            if (arrayItemMatch && currentKey) {
                if (!currentArrayItems) currentArrayItems = [];
                currentArrayItems.push(arrayItemMatch[1].trim());
                continue;
            }

            // Flush previous key if it had array items
            if (currentKey && currentArrayItems) {
                fields.push({ key: currentKey, value: currentArrayItems });
                currentKey = null;
                currentArrayItems = null;
            }

            // Key: value pair
            var kvMatch = line.match(/^([A-Za-z_][\w.-]*)\s*:\s*(.*)/);
            if (!kvMatch) continue;

            currentKey = kvMatch[1];
            var rawValue = kvMatch[2].trim();

            // Empty value — might have block array items following
            if (!rawValue) continue;

            // Flow array: [item1, item2]
            var flowMatch = rawValue.match(/^\[(.*)\]$/);
            if (flowMatch) {
                var items = flowMatch[1].split(',').map(function(s) {
                    return s.trim().replace(/^["']|["']$/g, '');
                }).filter(Boolean);
                fields.push({ key: currentKey, value: items });
                currentKey = null;
                continue;
            }

            // Strip quotes from scalar
            var scalar = rawValue.replace(/^["']|["']$/g, '');
            fields.push({ key: currentKey, value: scalar });
            currentKey = null;
        }

        // Flush last key
        if (currentKey && currentArrayItems) {
            fields.push({ key: currentKey, value: currentArrayItems });
        } else if (currentKey) {
            // Key with empty value
            fields.push({ key: currentKey, value: '' });
        }

        return fields;
    }

    var tagFields = ['tags', 'categories', 'keywords', 'labels'];
    var dateFields = ['date', 'updated', 'published', 'created', 'modified'];

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function formatDate(str) {
        // Try to parse as date
        var d = new Date(str);
        if (isNaN(d.getTime())) return escapeHtml(str);
        try {
            return new Intl.DateTimeFormat(undefined, {
                year: 'numeric', month: 'long', day: 'numeric'
            }).format(d);
        } catch (e) {
            return escapeHtml(str);
        }
    }

    function renderFrontMatterCard(fields) {
        var rows = '';
        for (var i = 0; i < fields.length; i++) {
            var field = fields[i];
            var key = field.key;
            var value = field.value;
            var valueHtml;

            if (Array.isArray(value) && tagFields.indexOf(key.toLowerCase()) !== -1) {
                // Render as pill list
                var pills = value.map(function(t) {
                    return '<li class="fm-tag">' + escapeHtml(t) + '</li>';
                }).join('');
                valueHtml = '<ul class="fm-tag-list">' + pills + '</ul>';
            } else if (Array.isArray(value)) {
                valueHtml = escapeHtml(value.join(', '));
            } else if (key.toLowerCase() === 'draft' && (value === 'true' || value === true)) {
                valueHtml = '<span class="fm-badge-draft">Draft</span>';
            } else if (dateFields.indexOf(key.toLowerCase()) !== -1) {
                valueHtml = formatDate(value);
            } else {
                valueHtml = escapeHtml(value);
            }

            rows += '<div class="fm-row"><dt class="fm-label">' +
                escapeHtml(key) + '</dt><dd class="fm-value">' +
                valueHtml + '</dd></div>';
        }

        return '<section id="front-matter" role="region" aria-label="Document metadata">' +
            '<dl class="fm-fields">' + rows + '</dl></section>';
    }

    /**
     * Adjusts data-sourcepos attributes by adding an offset.
     * This compensates for stripped front matter lines so gutter/line numbers
     * reference the original file line numbers.
     */
    function offsetSourcepos(container, offset) {
        if (!offset || !container) return;

        var elements = container.querySelectorAll('[data-sourcepos]');
        for (var i = 0; i < elements.length; i++) {
            var sp = elements[i].getAttribute('data-sourcepos');
            var match = sp.match(/^(\d+):(\d+)-(\d+):(\d+)$/);
            if (match) {
                var newStart = parseInt(match[1], 10) + offset;
                var newEnd = parseInt(match[3], 10) + offset;
                elements[i].setAttribute('data-sourcepos',
                    newStart + ':' + match[2] + '-' + newEnd + ':' + match[4]);
            }
        }
    }

    function setTheme(theme) {
        if (theme === currentTheme) return;
        currentTheme = theme;

        const stylesheet = document.getElementById('theme-stylesheet');
        if (stylesheet) {
            stylesheet.href = `../styles/${theme}.css`;
        }
        const highlightStylesheet = document.getElementById('highlight-stylesheet');
        if (highlightStylesheet) {
            highlightStylesheet.href = `../styles/highlight-${theme}.css`;
        }
        document.body.classList.remove('theme-light', 'theme-dark');
        document.body.classList.add(`theme-${theme}`);
    }

    /**
     * Optimize table column widths using min-content/max-content measurement.
     * Each column starts at its min-content width (longest word — no mid-word
     * breaks anywhere), then extra space is distributed proportionally to each
     * column's growth potential (max-content minus min-content).
     */
    function optimizeTableWidths(container) {
        var tables = container.querySelectorAll('table');
        for (var t = 0; t < tables.length; t++) {
            var table = tables[t];
            var rows = table.querySelectorAll('tr');
            if (rows.length === 0) continue;

            var numCols = rows[0].cells.length;
            if (numCols <= 1) continue;

            var containerStyle = getComputedStyle(container);
            var availWidth = container.clientWidth
                - parseFloat(containerStyle.paddingLeft)
                - parseFloat(containerStyle.paddingRight);
            if (availWidth <= 0) continue;

            var allCells = table.querySelectorAll('th, td');

            // Phase 1: Measure max-content (nowrap) widths per column
            table.style.tableLayout = 'auto';
            table.style.width = 'auto';
            for (var c = 0; c < allCells.length; c++) {
                allCells[c].style.whiteSpace = 'nowrap';
            }
            void table.offsetHeight;

            var maxContent = new Array(numCols).fill(0);
            for (var r = 0; r < rows.length; r++) {
                for (var i = 0; i < rows[r].cells.length && i < numCols; i++) {
                    var w = rows[r].cells[i].scrollWidth;
                    if (w > maxContent[i]) maxContent[i] = w;
                }
            }

            // Phase 2: Measure min-content (longest word) widths per column
            for (var c = 0; c < allCells.length; c++) {
                allCells[c].style.whiteSpace = '';
            }
            table.style.width = '0px';
            void table.offsetHeight;

            var minContent = new Array(numCols).fill(0);
            for (var r = 0; r < rows.length; r++) {
                for (var i = 0; i < rows[r].cells.length && i < numCols; i++) {
                    var w = rows[r].cells[i].scrollWidth;
                    if (w > minContent[i]) minContent[i] = w;
                }
            }

            // Reset table styles
            table.style.width = '';
            table.style.tableLayout = '';

            var totalMaxContent = 0;
            var totalMinContent = 0;
            for (var i = 0; i < numCols; i++) {
                totalMaxContent += maxContent[i];
                totalMinContent += minContent[i];
            }

            // Everything fits without wrapping — use auto layout
            if (totalMaxContent <= availWidth) {
                table.style.width = 'auto';
                continue;
            }

            // Even min-content exceeds container — let browser handle it
            if (totalMinContent >= availWidth) {
                table.style.width = '100%';
                continue;
            }

            // Phase 3: Distribute space. Start at min-content, distribute
            // extra space proportionally to each column's growth potential.
            var extraSpace = availWidth - totalMinContent;
            var totalGrowth = totalMaxContent - totalMinContent;

            var colgroup = document.createElement('colgroup');
            for (var i = 0; i < numCols; i++) {
                var col = document.createElement('col');
                var width = minContent[i];
                if (totalGrowth > 0) {
                    var growth = maxContent[i] - minContent[i];
                    width += Math.round((growth / totalGrowth) * extraSpace);
                }
                col.style.width = width + 'px';
                colgroup.appendChild(col);
            }

            var existing = table.querySelector('colgroup');
            if (existing) existing.remove();
            table.insertBefore(colgroup, table.firstChild);

            table.style.tableLayout = 'fixed';
            table.style.width = '100%';
        }
    }

    function resolveImagePaths(html, basePath, cacheBust) {
        if (!basePath) return html;

        // Add cache-bust query param if provided (for refresh)
        const cacheBustSuffix = cacheBust ? `?_cb=${cacheBust}` : '';

        // Check if basePath already has a scheme (e.g., redmargin-remote://)
        const hasScheme = basePath.includes('://');

        return html.replace(
            /(<img[^>]+src=["'])(?!https?:\/\/|data:)([^"']+)(["'])/gi,
            function(match, prefix, src, suffix) {
                if (src.startsWith('/')) return match;
                // If basePath already has scheme, use it directly; otherwise add file://
                const resolvedPath = hasScheme
                    ? `${basePath}/${src}${cacheBustSuffix}`
                    : `file://${basePath}/${src}${cacheBustSuffix}`;
                return prefix + resolvedPath + suffix;
            }
        );
    }


    function setGutterVisible(visible) {
        // Master switch - controls entire gutter including margin line
        const gutterContainer = document.getElementById('gutter-container');
        if (gutterContainer) {
            gutterContainer.style.display = visible ? '' : 'none';
        }
    }

    function setGitIndicatorsVisible(visible) {
        // Controls git change indicators only
        const gitGutter = document.getElementById('git-gutter');
        if (gitGutter) {
            gitGutter.style.display = visible ? '' : 'none';
        }
    }

    let lastCacheBust = 0;

    function render(payload) {
        const { markdown, options = {}, changes = null } = payload;
        const { theme = 'light', basePath = '', inlineCodeColor = 'warm', showGutter = true, showGitIndicators = true, textWidth = 'medium', contentWidth = 'unrestricted', cacheBust = 0 } = options;

        currentBasePath = basePath;
        setTheme(theme);
        setInlineCodeColor(inlineCodeColor);
        setGutterVisible(showGutter);
        setGitIndicatorsVisible(showGitIndicators);
        setContentWidths(textWidth, contentWidth);

        // Always store latest changes - RAF callback will use this instead of stale captured value
        latestChanges = changes;

        // Force re-render if cacheBust changed (user pressed refresh)
        const cacheBustChanged = cacheBust !== lastCacheBust;
        lastCacheBust = cacheBust;

        // Check if content actually changed
        const contentChanged = markdown !== lastRenderedMarkdown || cacheBustChanged;

        // Save scroll position before any DOM changes
        var savedScrollY = window.scrollY;

        if (contentChanged) {
            lastRenderedMarkdown = markdown;

            // Extract and strip front matter before rendering
            var fm = extractFrontMatter(markdown || '');
            lastFrontMatterOffset = fm.lineCount;

            let html = md.render(fm.body || '');
            // Sanitize HTML to prevent XSS from inline HTML in Markdown
            if (window.Sanitizer && window.Sanitizer.sanitize) {
                html = window.Sanitizer.sanitize(html);
            }
            html = resolveImagePaths(html, basePath, cacheBust);

            // Prepend front matter card if present
            if (fm.fields) {
                html = renderFrontMatterCard(fm.fields) + html;
            }

            const container = document.getElementById('content-container');
            if (container) {
                container.innerHTML = html;
                // Offset sourcepos attributes to match original file lines
                offsetSourcepos(container, lastFrontMatterOffset);
                optimizeTableWidths(container);
                // Remove for attributes from task list labels so clicking text
                // doesn't toggle the checkbox — only direct checkbox clicks should
                container.querySelectorAll('.task-list-item-label[for]').forEach(function(label) {
                    label.removeAttribute('for');
                });
            }

            // Use requestAnimationFrame to ensure DOM is updated
            requestAnimationFrame(function() {
                // Generate line numbers
                if (window.LineNumbers && window.LineNumbers.generate) {
                    window.LineNumbers.generate();
                }

                // Update git gutter markers with LATEST changes (not stale captured value)
                if (window.Gutter && window.Gutter.update) {
                    window.Gutter.update(latestChanges);
                }

                // Restore scroll position (skip if 0 — avoids overriding
                // ScrollPosition.restore which runs on a 50ms timeout)
                if (savedScrollY > 0) {
                    window.scrollTo(0, savedScrollY);
                }
            });
        } else {
            // Content unchanged - just update gutter markers
            if (window.Gutter && window.Gutter.update) {
                window.Gutter.update(changes);
            }
        }
    }

    const inlineCodeColors = {
        warm: { light: '#b45309', dark: '#f59e0b' },
        cool: { light: '#0369a1', dark: '#38bdf8' },
        rose: { light: '#be185d', dark: '#f472b6' },
        purple: { light: '#7c3aed', dark: '#a78bfa' },
        neutral: { light: '#525252', dark: '#a3a3a3' }
    };

    let currentInlineCodeColor = 'warm';

    function setInlineCodeColor(colorName) {
        if (!inlineCodeColors[colorName]) return;
        currentInlineCodeColor = colorName;
        const colors = inlineCodeColors[colorName];
        const color = currentTheme === 'dark' ? colors.dark : colors.light;
        document.documentElement.style.setProperty('--code-text', color);
    }

    const textWidthValues = {
        narrow: '580px',
        medium: '680px',
        wide: '800px',
        unrestricted: 'none'
    };

    const contentWidthValues = {
        medium: '800px',
        wide: '1100px',
        unrestricted: 'none'
    };

    function setContentWidths(textWidth, contentWidth) {
        const proseVal = textWidthValues[textWidth] || 'none';
        const wideVal = contentWidthValues[contentWidth] || 'none';
        document.documentElement.style.setProperty('--prose-max-width', proseVal);
        document.documentElement.style.setProperty('--content-max-width', wideVal);
    }

    // Re-apply inline code color when theme changes
    const originalSetTheme = setTheme;
    setTheme = function(theme) {
        originalSetTheme(theme);
        // Reapply inline code color for new theme
        const colors = inlineCodeColors[currentInlineCodeColor];
        if (colors) {
            const color = theme === 'dark' ? colors.dark : colors.light;
            document.documentElement.style.setProperty('--code-text', color);
        }
    };

    // Re-optimize table widths on window resize so tables reflow
    var resizeTimer;
    window.addEventListener('resize', function() {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(function() {
            var container = document.getElementById('content-container');
            if (container) {
                // Strip existing colgroups and inline styles before re-optimizing
                container.querySelectorAll('table').forEach(function(table) {
                    var cg = table.querySelector('colgroup');
                    if (cg) cg.remove();
                    table.style.tableLayout = '';
                    table.style.width = '';
                });
                optimizeTableWidths(container);
            }
        }, 100);
    });

    window.App = {
        render: render,
        setTheme: setTheme,
        setInlineCodeColor: setInlineCodeColor,
        getMarkdownIt: function() { return md; }
    };
})();
