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

    function render(payload) {
        const { markdown, options = {}, changes = null } = payload;
        const { theme = 'light', basePath = '' } = options;

        currentBasePath = basePath;
        setTheme(theme);

        // Always store latest changes - RAF callback will use this instead of stale captured value
        latestChanges = changes;

        // Check if content actually changed
        const contentChanged = markdown !== lastRenderedMarkdown;

        // Save scroll position before any DOM changes
        var savedScrollY = window.scrollY;

        if (contentChanged) {
            lastRenderedMarkdown = markdown;

            let html = md.render(markdown || '');
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

    window.App = {
        render: render,
        setTheme: setTheme,
        getMarkdownIt: function() { return md; }
    };
})();
