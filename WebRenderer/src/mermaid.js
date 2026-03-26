(function() {
    'use strict';

    var fallbackCopySvg = '<svg viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>';
    var fallbackCheckSvg = '<svg viewBox="0 0 24 24"><polyline points="20 6 9 17 4 12"/></svg>';
    var nextRenderId = 0;
    var activeThemeRenderGeneration = 0;

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function getCopySvg() {
        return window.RedmarginCopyIcons && window.RedmarginCopyIcons.copySvg
            ? window.RedmarginCopyIcons.copySvg
            : fallbackCopySvg;
    }

    function getCheckSvg() {
        return window.RedmarginCopyIcons && window.RedmarginCopyIcons.checkSvg
            ? window.RedmarginCopyIcons.checkSvg
            : fallbackCheckSvg;
    }

    function normalizeTheme(theme) {
        return theme === 'dark' ? 'dark' : 'default';
    }

    function getCurrentTheme() {
        if (document.body.classList.contains('theme-dark') ||
            document.body.classList.contains('print-dark-theme')) {
            return 'dark';
        }
        return 'default';
    }

    function isMermaidAvailable() {
        return typeof window.mermaid !== 'undefined' &&
            window.mermaid &&
            typeof window.mermaid.initialize === 'function' &&
            typeof window.mermaid.render === 'function';
    }

    function initialize(theme) {
        if (!isMermaidAvailable()) {
            return false;
        }

        window.mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            htmlLabels: false,
            suppressErrorRendering: true,
            theme: normalizeTheme(theme)
        });
        return true;
    }

    function getSanitizeMermaidSvg() {
        if (window.Sanitizer && typeof window.Sanitizer.sanitizeMermaidSvg === 'function') {
            return window.Sanitizer.sanitizeMermaidSvg;
        }
        return function(svgString) {
            return svgString;
        };
    }

    function createCopyButton() {
        var button = document.createElement('button');
        button.className = 'copy-btn';
        button.innerHTML = getCopySvg();
        button.setAttribute('aria-label', 'Copy Mermaid source');
        button.addEventListener('click', handleCopyClick);
        return button;
    }

    function handleCopyClick(event) {
        var button = event.currentTarget;
        var block = button.closest('.mermaid-block');
        if (!block || !window.navigator.clipboard || !window.navigator.clipboard.writeText) {
            return;
        }

        var source = block.getAttribute('data-source') || '';
        window.navigator.clipboard.writeText(source).then(function() {
            button.innerHTML = getCheckSvg();
            setTimeout(function() {
                button.innerHTML = getCopySvg();
            }, 1500);
        });
    }

    function ensureCopyButton(block) {
        var existing = block.querySelector('.copy-btn');
        if (existing) {
            existing.remove();
        }
        block.appendChild(createCopyButton());
    }

    function renderPlainSource(block) {
        var source = block.getAttribute('data-source') || '';
        block.innerHTML = '<pre><code class="language-mermaid">' + escapeHtml(source) + '</code></pre>';
        ensureCopyButton(block);
    }

    function renderErrorState(block, error) {
        var source = block.getAttribute('data-source') || '';
        var message = error && error.message ? error.message : String(error || 'Mermaid render failed');
        block.innerHTML = '<div class="mermaid-error">' + escapeHtml(message) + '</div>' +
            '<pre><code class="language-mermaid">' + escapeHtml(source) + '</code></pre>';
        ensureCopyButton(block);
    }

    function insertRenderedSvg(block, svgString) {
        block.innerHTML = svgString;
        ensureCopyButton(block);
    }

    async function renderSingleBlock(block, generation) {
        if (generation !== null && generation !== activeThemeRenderGeneration) {
            return false;
        }

        var source = block.getAttribute('data-source') || '';
        if (!source.trim()) {
            renderErrorState(block, new Error('Mermaid source is empty'));
            return true;
        }

        if (!isMermaidAvailable()) {
            renderPlainSource(block);
            return true;
        }

        var renderResult = await window.mermaid.render(
            'redmargin-mermaid-' + (++nextRenderId),
            source
        );

        if (generation !== null && generation !== activeThemeRenderGeneration) {
            return false;
        }

        var sanitizeMermaidSvg = getSanitizeMermaidSvg();
        var svgString = sanitizeMermaidSvg(renderResult.svg || '');
        if (!svgString.trim()) {
            throw new Error('Mermaid render produced empty SVG output');
        }

        insertRenderedSvg(block, svgString);
        return true;
    }

    async function renderBlocksInternal(theme, generation) {
        var blocks = document.querySelectorAll('.mermaid-block');
        if (blocks.length === 0) {
            return;
        }

        initialize(theme || getCurrentTheme());

        for (var i = 0; i < blocks.length; i++) {
            if (generation !== null && generation !== activeThemeRenderGeneration) {
                return;
            }

            try {
                var completed = await renderSingleBlock(blocks[i], generation);
                if (completed === false) {
                    return;
                }
            } catch (error) {
                if (generation !== null && generation !== activeThemeRenderGeneration) {
                    return;
                }
                renderErrorState(blocks[i], error);
            }
        }
    }

    function renderBlocks() {
        return renderBlocksInternal(getCurrentTheme(), null);
    }

    function rerenderForTheme(theme) {
        activeThemeRenderGeneration += 1;
        return renderBlocksInternal(theme, activeThemeRenderGeneration);
    }

    function prepareMermaidForPrint(theme) {
        return rerenderForTheme(theme);
    }

    function restoreMermaidFromPrint(screenTheme) {
        return rerenderForTheme(screenTheme);
    }

    window.MermaidRenderer = {
        initialize: initialize,
        renderBlocks: renderBlocks,
        rerenderForTheme: rerenderForTheme,
        prepareMermaidForPrint: prepareMermaidForPrint,
        restoreMermaidFromPrint: restoreMermaidFromPrint
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = window.MermaidRenderer;
    }
})();
