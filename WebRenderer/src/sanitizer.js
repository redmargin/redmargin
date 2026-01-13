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

    // Allowed URL schemes for href (explicit allowlist)
    const ALLOWED_HREF_SCHEMES = new Set(['http:', 'https:', 'mailto:']);

    // Allowed URL schemes for img src (explicit allowlist)
    const ALLOWED_SRC_SCHEMES = new Set(['http:', 'https:', 'file:']);

    // Event handler pattern
    const EVENT_HANDLER = /^on/i;

    /**
     * Extract scheme from URL, returns null for relative URLs
     */
    function getUrlScheme(url) {
        if (!url) return null;
        const trimmed = url.trim();
        // Relative URLs (no scheme)
        if (trimmed.startsWith('/') || trimmed.startsWith('.') ||
            trimmed.startsWith('#') || trimmed.startsWith('?') ||
            !trimmed.includes(':')) {
            return null;
        }
        const colonIndex = trimmed.indexOf(':');
        // Schemes are typically short (http, https, file, mailto, javascript, etc.)
        // Allow up to 11 chars to cover 'javascript:' (10 chars + colon)
        if (colonIndex > 0 && colonIndex <= 11) {
            return trimmed.substring(0, colonIndex + 1).toLowerCase();
        }
        return null;
    }

    /**
     * Check if a URL is safe for href attribute (allowlist approach)
     */
    function isSafeHref(url) {
        if (!url) return true;
        const scheme = getUrlScheme(url);
        // Allow relative URLs
        if (scheme === null) return true;
        // Allow data: URLs only with specific handling (not in href)
        if (scheme === 'data:') return false;
        // Check against allowlist
        return ALLOWED_HREF_SCHEMES.has(scheme);
    }

    /**
     * Check if a URL is safe for src attribute (allowlist approach)
     */
    function isSafeSrc(url) {
        if (!url) return true;
        const scheme = getUrlScheme(url);
        // Allow relative URLs
        if (scheme === null) return true;
        // data: URLs handled separately in isSafeDataUrl
        if (scheme === 'data:') return true;
        // Check against allowlist
        return ALLOWED_SRC_SCHEMES.has(scheme);
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
            // Only safe raster formats - NOT svg+xml (can contain scripts)
            return /^data:image\/(png|jpeg|jpg|gif|webp);/i.test(trimmed);
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

            // Validate URLs in href and src using allowlist
            if (attrName === 'href') {
                const url = attr.value;
                if (!isSafeHref(url)) {
                    console.log('[Sanitizer] Blocked href scheme:', url.substring(0, 50));
                    attrsToRemove.push(attr.name);
                    continue;
                }
            }
            if (attrName === 'src') {
                const url = attr.value;
                if (!isSafeSrc(url)) {
                    console.log('[Sanitizer] Blocked src scheme:', url.substring(0, 50));
                    attrsToRemove.push(attr.name);
                    continue;
                }
                // Additional check for data URLs (only safe image types)
                if (!isSafeDataUrl(url, tagName)) {
                    console.log('[Sanitizer] Blocked data URL for', tagName + ':', url.substring(0, 50));
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
        module.exports = { sanitize, isSafeHref, isSafeSrc, getUrlScheme };
    } else {
        window.Sanitizer = { sanitize };
    }
})();
