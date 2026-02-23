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

            var availWidth = container.clientWidth;
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
