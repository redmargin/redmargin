/**
 * highlight.js integration for markdown-it
 * Provides syntax highlighting for fenced code blocks
 */
(function() {
    'use strict';

    /**
     * Highlight function for markdown-it
     * @param {string} code - The code to highlight
     * @param {string} lang - The language identifier
     * @returns {string} - Highlighted HTML or empty string for default escaping
     */
    function highlight(code, lang) {
        if (!window.hljs) {
            return '';
        }

        // Normalize language name
        const language = lang ? lang.toLowerCase().trim() : '';

        // If language specified and supported, highlight it
        if (language && window.hljs.getLanguage(language)) {
            try {
                const result = window.hljs.highlight(code, { language: language });
                return result.value;
            } catch (e) {
                // Fall through to auto-detection or plain
            }
        }

        // For unspecified or unsupported languages, return empty string
        // This tells markdown-it to use default escaping
        return '';
    }

    // Export for use by index.js
    window.highlightCode = highlight;
})();
