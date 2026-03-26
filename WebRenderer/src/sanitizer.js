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
        'th': ['colspan', 'rowspan', 'scope', 'style'],
        'td': ['colspan', 'rowspan', 'style'],
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
    const GLOBAL_ATTRS = ['data-sourcepos', 'data-source', 'id', 'class'];

    // Allowed URL schemes for href (explicit allowlist)
    const ALLOWED_HREF_SCHEMES = new Set(['http:', 'https:', 'mailto:']);

    // Allowed URL schemes for img src (explicit allowlist)
    const ALLOWED_SRC_SCHEMES = new Set(['http:', 'https:', 'file:']);

    // Event handler pattern
    const EVENT_HANDLER = /^on/i;

    const ALLOWED_SVG_TAGS = new Set([
        'svg', 'g', 'path', 'rect', 'circle', 'ellipse', 'line',
        'polyline', 'polygon', 'text', 'tspan', 'defs', 'marker',
        'use', 'clippath', 'mask', 'pattern', 'lineargradient',
        'radialgradient', 'stop', 'title', 'desc', 'style'
    ]);

    const ALLOWED_SVG_ATTRS = new Set([
        'id', 'class', 'role', 'tabindex', 'focusable',
        'xmlns', 'xmlns:xlink', 'xml:space', 'version',
        'viewbox', 'width', 'height', 'x', 'y', 'x1', 'y1', 'x2', 'y2',
        'cx', 'cy', 'r', 'rx', 'ry', 'dx', 'dy',
        'd', 'points', 'pathlength',
        'fill', 'fill-opacity', 'fill-rule',
        'stroke', 'stroke-opacity', 'stroke-width',
        'stroke-dasharray', 'stroke-dashoffset',
        'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit',
        'opacity', 'transform', 'preserveaspectratio',
        'marker-start', 'marker-mid', 'marker-end',
        'markerwidth', 'markerheight', 'markerunits', 'orient',
        'refx', 'refy', 'mask', 'maskunits', 'maskcontentunits',
        'clip-path', 'clippathunits',
        'patternunits', 'patterncontentunits', 'patterntransform',
        'gradientunits', 'gradienttransform',
        'offset', 'stop-color', 'stop-opacity',
        'font-family', 'font-size', 'font-weight', 'font-style',
        'text-anchor', 'dominant-baseline', 'alignment-baseline',
        'baseline-shift', 'letter-spacing', 'word-spacing',
        'textlength', 'lengthadjust', 'direction', 'white-space',
        'shape-rendering', 'color-rendering', 'color-interpolation',
        'vector-effect', 'href', 'xlink:href', 'style'
    ]);

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

    function isUnsafeSvgUrl(url) {
        if (!url) return false;
        const trimmed = url.trim();
        return /^javascript:/i.test(trimmed) ||
            /^data:/i.test(trimmed) ||
            /url\(\s*['"]?\s*(javascript:|data:)/i.test(trimmed);
    }

    function isSafeMermaidStyle(styleValue) {
        if (!styleValue) return true;
        return !/(?:expression\s*\(|@import|javascript:|data:|url\(\s*['"]?\s*(?!#))/i.test(styleValue);
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

    function sanitizeMermaidSvg(svgString) {
        if (!svgString || typeof svgString !== 'string') return '';

        const parser = new DOMParser();
        const doc = parser.parseFromString(svgString, 'image/svg+xml');
        let root = doc.documentElement;

        if (!root) return '';
        if (root.tagName && root.tagName.toLowerCase() === 'parsererror') {
            return '';
        }
        if (root.tagName.toLowerCase() !== 'svg') {
            root = doc.querySelector('svg');
            if (!root) return '';
        }

        sanitizeMermaidSvgAttributes(root);
        sanitizeMermaidSvgNode(root);
        return new XMLSerializer().serializeToString(root);
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

            // Validate style attribute on table cells (only text-align allowed)
            if (attrName === 'style' && (tagName === 'th' || tagName === 'td')) {
                const style = attr.value.toLowerCase().replace(/\s/g, '');
                if (!/^text-align:(left|center|right);?$/.test(style)) {
                    attrsToRemove.push(attr.name);
                    continue;
                }
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

    function sanitizeMermaidSvgNode(node) {
        if (!node) return;

        const nodesToRemove = [];
        for (let i = 0; i < node.childNodes.length; i++) {
            const child = node.childNodes[i];
            if (child.nodeType !== Node.ELEMENT_NODE) {
                continue;
            }

            const tagName = child.tagName.toLowerCase();
            if (tagName === 'script' || tagName === 'foreignobject' || tagName === 'iframe') {
                nodesToRemove.push(child);
                continue;
            }

            if (!ALLOWED_SVG_TAGS.has(tagName)) {
                nodesToRemove.push(child);
                continue;
            }

            if (tagName === 'style' && !isSafeMermaidStyle(child.textContent || '')) {
                nodesToRemove.push(child);
                continue;
            }

            sanitizeMermaidSvgAttributes(child);
            sanitizeMermaidSvgNode(child);
        }

        for (const child of nodesToRemove) {
            child.remove();
        }
    }

    function sanitizeMermaidSvgAttributes(element) {
        const attrsToRemove = [];

        for (let i = 0; i < element.attributes.length; i++) {
            const attr = element.attributes[i];
            const attrName = attr.name.toLowerCase();
            const value = attr.value || '';

            if (EVENT_HANDLER.test(attrName)) {
                attrsToRemove.push(attr.name);
                continue;
            }

            const isAllowed = ALLOWED_SVG_ATTRS.has(attrName) ||
                attrName.startsWith('aria-') ||
                attrName.startsWith('data-');

            if (!isAllowed) {
                attrsToRemove.push(attr.name);
                continue;
            }

            if ((attrName === 'href' || attrName === 'xlink:href') && isUnsafeSvgUrl(value)) {
                attrsToRemove.push(attr.name);
                continue;
            }

            if (attrName === 'style' && !isSafeMermaidStyle(value)) {
                attrsToRemove.push(attr.name);
                continue;
            }

            if (
                (attrName === 'fill' ||
                 attrName === 'stroke' ||
                 attrName === 'mask' ||
                 attrName === 'clip-path' ||
                 attrName === 'marker-start' ||
                 attrName === 'marker-mid' ||
                 attrName === 'marker-end') &&
                isUnsafeSvgUrl(value)
            ) {
                attrsToRemove.push(attr.name);
            }
        }

        for (const attrName of attrsToRemove) {
            element.removeAttribute(attrName);
        }
    }

    // Export for browser and Node.js
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = {
            sanitize,
            sanitizeMermaidSvg,
            isSafeHref,
            isSafeSrc,
            getUrlScheme
        };
    } else {
        window.Sanitizer = {
            sanitize,
            sanitizeMermaidSvg
        };
    }
})();
