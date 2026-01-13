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
        breaks: false
    });

    md.use(window.markdownitTaskLists, { enabled: true, label: true });
    md.use(window.sourceposPlugin);

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
        document.body.classList.remove('theme-light', 'theme-dark');
        document.body.classList.add(`theme-${theme}`);
    }

    function resolveImagePaths(html, basePath) {
        if (!basePath) return html;

        return html.replace(
            /(<img[^>]+src=["'])(?!https?:\/\/|data:)([^"']+)(["'])/gi,
            function(match, prefix, src, suffix) {
                if (src.startsWith('/')) return match;
                const resolvedPath = `file://${basePath}/${src}`;
                return prefix + resolvedPath + suffix;
            }
        );
    }


    function setGutterVisible(visible) {
        const gutterContainer = document.getElementById('gutter-container');
        if (gutterContainer) {
            gutterContainer.style.display = visible ? '' : 'none';
        }
    }

    function render(payload) {
        const { markdown, options = {}, changes = null } = payload;
        const { theme = 'light', basePath = '', inlineCodeColor = 'warm', showGutter = true } = options;

        currentBasePath = basePath;
        setTheme(theme);
        setInlineCodeColor(inlineCodeColor);
        setGutterVisible(showGutter);

        // Always store latest changes - RAF callback will use this instead of stale captured value
        latestChanges = changes;

        // Check if content actually changed
        const contentChanged = markdown !== lastRenderedMarkdown;

        // Save scroll position before any DOM changes
        var savedScrollY = window.scrollY;

        if (contentChanged) {
            lastRenderedMarkdown = markdown;

            let html = md.render(markdown || '');
            // Sanitize HTML to prevent XSS from inline HTML in Markdown
            if (window.Sanitizer && window.Sanitizer.sanitize) {
                html = window.Sanitizer.sanitize(html);
            }
            html = resolveImagePaths(html, basePath);

            const container = document.getElementById('content-container');
            if (container) {
                container.innerHTML = html;
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
