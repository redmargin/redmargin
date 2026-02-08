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
    md.use(window.sourceposPlugin);
    md.use(window.headingAnchorsPlugin);

    let currentTheme = 'light';
    let currentBasePath = '';
    let lastRenderedMarkdown = null;
    let latestChanges = null;  // Always use latest changes for gutter

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
     * Optimize table column widths: short-content columns stay tight,
     * all others share remaining space proportionally to their content.
     * Uses colgroup + table-layout: fixed for precise control.
     */
    function optimizeTableWidths(container) {
        var tables = container.querySelectorAll('table');
        for (var t = 0; t < tables.length; t++) {
            var table = tables[t];
            var rows = table.querySelectorAll('tr');
            if (rows.length === 0) continue;

            var numCols = rows[0].cells.length;
            if (numCols <= 1) continue;

            var availWidth = container.clientWidth;
            if (availWidth <= 0) continue;

            // Temporarily set nowrap + auto width to measure natural content widths
            var origWidth = table.style.width;
            table.style.width = 'auto';
            var allCells = table.querySelectorAll('th, td');
            for (var c = 0; c < allCells.length; c++) {
                allCells[c].style.whiteSpace = 'nowrap';
            }
            void table.offsetHeight;

            var colWidths = new Array(numCols).fill(0);
            for (var r = 0; r < rows.length; r++) {
                for (var i = 0; i < rows[r].cells.length && i < numCols; i++) {
                    var w = rows[r].cells[i].scrollWidth;
                    if (w > colWidths[i]) colWidths[i] = w;
                }
            }

            // Restore
            for (var c = 0; c < allCells.length; c++) {
                allCells[c].style.whiteSpace = '';
            }

            var totalNatural = 0;
            for (var i = 0; i < numCols; i++) totalNatural += colWidths[i];

            if (totalNatural <= availWidth) {
                table.style.width = 'auto';
                continue;
            }

            // Short columns (under 100px) get their exact natural width.
            // Everything else shares remaining space proportionally.
            var shortThreshold = 100;
            var fixedTotal = 0;
            var flexTotal = 0;
            var isFixed = [];

            for (var i = 0; i < numCols; i++) {
                if (colWidths[i] <= shortThreshold) {
                    isFixed.push(true);
                    fixedTotal += colWidths[i];
                } else {
                    isFixed.push(false);
                    flexTotal += colWidths[i];
                }
            }

            // If everything is "short", just pick widest as flex
            if (flexTotal === 0) {
                var maxIdx = 0;
                for (var i = 1; i < numCols; i++) {
                    if (colWidths[i] > colWidths[maxIdx]) maxIdx = i;
                }
                isFixed[maxIdx] = false;
                fixedTotal -= colWidths[maxIdx];
                flexTotal = colWidths[maxIdx];
            }

            var flexSpace = availWidth - fixedTotal;

            var colgroup = document.createElement('colgroup');
            for (var i = 0; i < numCols; i++) {
                var col = document.createElement('col');
                if (isFixed[i]) {
                    col.style.width = colWidths[i] + 'px';
                } else {
                    var share = Math.round((colWidths[i] / flexTotal) * flexSpace);
                    col.style.width = Math.max(share, 40) + 'px';
                }
                colgroup.appendChild(col);
            }

            var existing = table.querySelector('colgroup');
            if (existing) existing.remove();
            table.insertBefore(colgroup, table.firstChild);

            // Headers should never wrap
            var headers = table.querySelectorAll('th');
            for (var h = 0; h < headers.length; h++) {
                headers[h].style.whiteSpace = 'nowrap';
            }

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
        const { theme = 'light', basePath = '', inlineCodeColor = 'warm', showGutter = true, showGitIndicators = true, cacheBust = 0 } = options;

        currentBasePath = basePath;
        setTheme(theme);
        setInlineCodeColor(inlineCodeColor);
        setGutterVisible(showGutter);
        setGitIndicatorsVisible(showGitIndicators);

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

            let html = md.render(markdown || '');
            // Sanitize HTML to prevent XSS from inline HTML in Markdown
            if (window.Sanitizer && window.Sanitizer.sanitize) {
                html = window.Sanitizer.sanitize(html);
            }
            html = resolveImagePaths(html, basePath, cacheBust);

            const container = document.getElementById('content-container');
            if (container) {
                container.innerHTML = html;
                optimizeTableWidths(container);
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

                // Restore scroll position
                window.scrollTo(0, savedScrollY);
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

    window.App = {
        render: render,
        setTheme: setTheme,
        setInlineCodeColor: setInlineCodeColor,
        getMarkdownIt: function() { return md; }
    };
})();
