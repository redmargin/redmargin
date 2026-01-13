/**
 * HTML Sanitizer for RedMargin
 * Allowlist-based sanitizer to prevent XSS from Markdown content.
 */
(function() {
    'use strict';

    // Allowed tags (lowercase)
    const ALLOWED_TAGS = new Set([
        'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'ul', 'ol', 'li',
        'a', 'img',
        'table', 'thead', 'tbody', 'tr', 'th', 'td',
        'code', 'pre', 'blockquote',
        'em', 'strong', 'del', 's',
        'input', 'label',
        'br', 'hr',
        'div', 'span',
        'sup', 'sub',
        'dl', 'dt', 'dd',
        'figure', 'figcaption',
        'abbr', 'cite', 'dfn', 'kbd', 'mark', 'q', 'samp', 'var', 'wbr',
        'details', 'summary',
        'caption', 'col', 'colgroup'
    ]);

    // Allowed attributes per tag
    const ALLOWED_ATTRS = {
        'a': ['href', 'title'],
        'img': ['src', 'alt', 'title', 'width', 'height'],
        'input': ['type', 'checked', 'disabled'],
        'label': ['for'],
        'th': ['colspan', 'rowspan', 'scope'],
        'td': ['colspan', 'rowspan'],
        'col': ['span'],
        'colgroup': ['span'],
        'abbr': ['title'],
        'dfn': ['title'],
        'q': ['cite'],
        'blockquote': ['cite'],
        'ol': ['start', 'type', 'reversed'],
        'li': ['value']
    };

    // Global attributes allowed on all elements
    const GLOBAL_ATTRS = ['data-sourcepos', 'id', 'class'];

    // Dangerous URL schemes (data: handled separately for images)
    const DANGEROUS_SCHEMES = /^(javascript|vbscript):/i;

    // Event handler pattern
    const EVENT_HANDLER = /^on/i;

    /**
     * Check if a URL is safe
     */
    function isSafeUrl(url) {
        if (!url) return true;
        const trimmed = url.trim().toLowerCase();
        // Allow data: URLs for images only (handled separately)
        return !DANGEROUS_SCHEMES.test(trimmed);
    }

    /**
     * Check if a data URL is a safe image
     */
    function isSafeDataUrl(url, tagName) {
        if (!url) return true;
        const trimmed = url.trim().toLowerCase();
        if (!trimmed.startsWith('data:')) return true;
        // Only allow data URLs for images, and only image MIME types
        if (tagName === 'img') {
            return /^data:image\/(png|jpeg|jpg|gif|webp|svg\+xml|bmp|ico);/i.test(trimmed);
        }
        return false;
    }

    /**
     * Sanitize HTML string
     */
    function sanitize(html) {
        if (!html || typeof html !== 'string') return '';

        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');

        sanitizeNode(doc.body);

        return doc.body.innerHTML;
    }

    /**
     * Recursively sanitize a DOM node
     */
    function sanitizeNode(node) {
        if (!node) return;

        const nodesToRemove = [];

        for (let i = 0; i < node.childNodes.length; i++) {
            const child = node.childNodes[i];

            if (child.nodeType === Node.ELEMENT_NODE) {
                const tagName = child.tagName.toLowerCase();

                // Remove script, style, and other dangerous tags entirely
                if (tagName === 'script' || tagName === 'style' ||
                    tagName === 'iframe' || tagName === 'object' ||
                    tagName === 'embed' || tagName === 'form' ||
                    tagName === 'frame' || tagName === 'frameset' ||
                    tagName === 'meta' || tagName === 'link' ||
                    tagName === 'base' || tagName === 'applet') {
                    nodesToRemove.push(child);
                    continue;
                }

                // For non-allowed tags, unwrap (keep children, remove tag)
                if (!ALLOWED_TAGS.has(tagName)) {
                    // Process children first
                    sanitizeNode(child);
                    // Replace with children
                    while (child.firstChild) {
                        node.insertBefore(child.firstChild, child);
                    }
                    nodesToRemove.push(child);
                    continue;
                }

                // Special handling for input - only allow checkboxes
                if (tagName === 'input') {
                    const type = child.getAttribute('type');
                    if (type !== 'checkbox') {
                        nodesToRemove.push(child);
                        continue;
                    }
                }

                // Sanitize attributes
                sanitizeAttributes(child, tagName);

                // Recurse into children
                sanitizeNode(child);
            }
        }

        // Remove marked nodes
        for (const toRemove of nodesToRemove) {
            toRemove.remove();
        }
    }

    /**
     * Sanitize attributes on an element
     */
    function sanitizeAttributes(element, tagName) {
        const allowedForTag = ALLOWED_ATTRS[tagName] || [];
        const attrsToRemove = [];

        for (let i = 0; i < element.attributes.length; i++) {
            const attr = element.attributes[i];
            const attrName = attr.name.toLowerCase();

            // Remove event handlers
            if (EVENT_HANDLER.test(attrName)) {
                attrsToRemove.push(attr.name);
                continue;
            }

            // Check if attribute is allowed
            const isAllowed = allowedForTag.includes(attrName) ||
                              GLOBAL_ATTRS.includes(attrName);

            if (!isAllowed) {
                attrsToRemove.push(attr.name);
                continue;
            }

            // Validate URLs in href and src
            if (attrName === 'href' || attrName === 'src') {
                const url = attr.value;
                if (!isSafeUrl(url)) {
                    attrsToRemove.push(attr.name);
                    continue;
                }
                // Additional check for data URLs
                if (!isSafeDataUrl(url, tagName)) {
                    attrsToRemove.push(attr.name);
                    continue;
                }
            }
        }

        // Remove disallowed attributes
        for (const attrName of attrsToRemove) {
            element.removeAttribute(attrName);
        }
    }

    // Export for browser and Node.js
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { sanitize, isSafeUrl };
    } else {
        window.Sanitizer = { sanitize };
    }
})();
