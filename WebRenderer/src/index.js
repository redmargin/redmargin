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

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function getFenceSourcepos(token) {
        if (!token || !token.map) {
            return token && token.attrGet ? token.attrGet('data-sourcepos') : '';
        }

        var startLine = token.map[0] + 1;
        var endLine = token.map[1];
        var fenceLength = (token.markup || '```').length;
        return startLine + ':1-' + endLine + ':' + fenceLength;
    }

    function isRawHtmlFenceInfo(info) {
        return info === '{=html}' || info === '=html';
    }

    var defaultFenceRenderer = md.renderer.rules.fence || function(tokens, idx, options, env, self) {
        return self.renderToken(tokens, idx, options);
    };

    md.renderer.rules.fence = function(tokens, idx, options, env, self) {
        var token = tokens[idx];
        var info = (token.info || '').trim();

        if (isRawHtmlFenceInfo(info)) {
            var rawSourcepos = getFenceSourcepos(token);
            return '<div class="raw-html-block"' +
                (rawSourcepos ? ' data-sourcepos="' + escapeHtml(rawSourcepos) + '"' : '') +
                '>' + (token.content || '') + '</div>';
        }

        if (info !== 'mermaid') {
            return defaultFenceRenderer(tokens, idx, options, env, self);
        }

        var sourcepos = getFenceSourcepos(token);
        return '<div class="mermaid-block"' +
            (sourcepos ? ' data-sourcepos="' + escapeHtml(sourcepos) + '"' : '') +
            ' data-source="' + escapeHtml(token.content || '') + '"></div>';
    };

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

    function applyThemeStyles(theme) {
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

        const colors = inlineCodeColors[currentInlineCodeColor];
        if (colors) {
            const color = theme === 'dark' ? colors.dark : colors.light;
            document.documentElement.style.setProperty('--code-text', color);
        }
    }

    function refreshRenderedOverlays(savedScrollY) {
        if (window.LineNumbers && window.LineNumbers.generate) {
            window.LineNumbers.generate();
        }

        if (window.Gutter && window.Gutter.update) {
            window.Gutter.update(latestChanges);
        }

        if (typeof savedScrollY === 'number' && savedScrollY > 0) {
            window.scrollTo(0, savedScrollY);
        }
    }

    function renderMermaidAndRefresh(savedScrollY) {
        var renderPromise = Promise.resolve();
        if (window.MermaidRenderer && window.MermaidRenderer.renderBlocks) {
            renderPromise = window.MermaidRenderer.renderBlocks();
        }

        return renderPromise.then(function() {
            refreshRenderedOverlays(savedScrollY);
        }).catch(function(error) {
            console.error('[MermaidRenderer] Render failed', error);
            refreshRenderedOverlays(savedScrollY);
        });
    }

    function afterDomUpdate(callback) {
        var didRun = false;

        function runOnce() {
            if (didRun) {
                return;
            }
            didRun = true;
            callback();
        }

        if (typeof requestAnimationFrame === 'function') {
            requestAnimationFrame(runOnce);
            setTimeout(runOnce, 50);
        } else {
            setTimeout(runOnce, 0);
        }
    }

    function rerenderMermaidForTheme(theme, savedScrollY) {
        var renderPromise = Promise.resolve();
        if (window.MermaidRenderer && window.MermaidRenderer.rerenderForTheme) {
            renderPromise = window.MermaidRenderer.rerenderForTheme(theme);
        }

        return renderPromise.then(function() {
            refreshRenderedOverlays(savedScrollY);
        }).catch(function(error) {
            console.error('[MermaidRenderer] Theme rerender failed', error);
            refreshRenderedOverlays(savedScrollY);
        });
    }

    function setTheme(theme) {
        var themeChanged = theme !== currentTheme;
        applyThemeStyles(theme);

        if (!themeChanged) {
            return Promise.resolve();
        }

        return rerenderMermaidForTheme(theme);
    }

    function optimizeTableWidths(container) {
        var tables = container.querySelectorAll('table');
        for (var t = 0; t < tables.length; t++) {
            var table = tables[t];
            var rows = table.querySelectorAll('tr');
            if (rows.length === 0) continue;

            var numCols = rows[0].cells.length;
            if (numCols <= 1) continue;

            var containerStyle = window.getComputedStyle
                ? window.getComputedStyle(container)
                : { paddingLeft: '0', paddingRight: '0' };
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

    var copySvg = '<svg viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>';
    var checkSvg = '<svg viewBox="0 0 24 24"><polyline points="20 6 9 17 4 12"/></svg>';
    window.RedmarginCopyIcons = {
        copySvg: copySvg,
        checkSvg: checkSvg
    };

    function addCopyButtons(container) {
        var pres = container.querySelectorAll('pre');
        for (var i = 0; i < pres.length; i++) {
            var pre = pres[i];
            var btn = document.createElement('button');
            btn.className = 'copy-btn';
            btn.innerHTML = copySvg;
            btn.setAttribute('aria-label', 'Copy code');
            btn.addEventListener('click', handleCopyClick);
            pre.appendChild(btn);
        }
    }

    function handleCopyClick(e) {
        var btn = e.currentTarget;
        var pre = btn.closest('pre');
        var code = pre.querySelector('code');
        var text = (code || pre).textContent;
        window.navigator.clipboard.writeText(text).then(function() {
            btn.innerHTML = checkSvg;
            setTimeout(function() { btn.innerHTML = copySvg; }, 1500);
        });
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
        var themeChanged = theme !== currentTheme;
        applyThemeStyles(theme);
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
            var fm = window.FrontMatter
                ? window.FrontMatter.extract(markdown || '')
                : { body: markdown || '', fields: null, lineCount: 0 };
            lastFrontMatterOffset = fm.lineCount;

            let html = md.render(fm.body || '');
            // Sanitize HTML to prevent XSS from inline HTML in Markdown
            if (window.Sanitizer && window.Sanitizer.sanitize) {
                html = window.Sanitizer.sanitize(html);
            }
            html = resolveImagePaths(html, basePath, cacheBust);

            // Prepend front matter card if present
            if (fm.fields) {
                html = window.FrontMatter.renderCard(fm.fields) + html;
            }

            const container = document.getElementById('content-container');
            if (container) {
                container.innerHTML = html;
                // Offset sourcepos attributes to match original file lines
                offsetSourcepos(container, lastFrontMatterOffset);
                optimizeTableWidths(container);
                addCopyButtons(container);
                // Remove for attributes from task list labels so clicking text
                // doesn't toggle the checkbox — only direct checkbox clicks should
                container.querySelectorAll('.task-list-item-label[for]').forEach(function(label) {
                    label.removeAttribute('for');
                });
            }

            afterDomUpdate(function() {
                renderMermaidAndRefresh(savedScrollY);
            });
        } else {
            if (themeChanged) {
                rerenderMermaidForTheme(theme);
            } else if (window.Gutter && window.Gutter.update) {
                window.Gutter.update(latestChanges);
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
