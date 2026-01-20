/**
 * Simple markdown-it plugin to add id attributes to headings.
 * Converts heading text to a slug for the id.
 */
(function() {
    'use strict';

    /**
     * Slugify a string for use as an HTML id.
     * Converts to lowercase, replaces spaces with hyphens, removes special chars.
     */
    function slugify(text) {
        return text
            .toLowerCase()
            .trim()
            .replace(/[^\w\s-]/g, '')  // Remove special characters
            .replace(/\s+/g, '-')       // Replace spaces with hyphens
            .replace(/-+/g, '-')        // Replace multiple hyphens with single
            .replace(/^-|-$/g, '');     // Remove leading/trailing hyphens
    }

    /**
     * markdown-it plugin that adds id attributes to heading elements.
     */
    function headingAnchorsPlugin(md) {
        // Track used slugs to handle duplicates
        const usedSlugs = new Map();

        // Reset slugs on each render
        md.core.ruler.push('reset-heading-slugs', function() {
            usedSlugs.clear();
        });

        // Override heading_open renderer to add id
        const defaultRender = md.renderer.rules.heading_open ||
            function(tokens, idx, options, env, self) {
                return self.renderToken(tokens, idx, options);
            };

        md.renderer.rules.heading_open = function(tokens, idx, options, env, self) {
            const token = tokens[idx];
            const contentToken = tokens[idx + 1];

            if (contentToken && contentToken.type === 'inline' && contentToken.content) {
                let slug = slugify(contentToken.content);

                // Handle duplicate slugs by appending a number
                if (usedSlugs.has(slug)) {
                    const count = usedSlugs.get(slug) + 1;
                    usedSlugs.set(slug, count);
                    slug = `${slug}-${count}`;
                } else {
                    usedSlugs.set(slug, 0);
                }

                // Add id attribute
                token.attrSet('id', slug);
            }

            return defaultRender(tokens, idx, options, env, self);
        };
    }

    // Export for browser and Node.js
    if (typeof window !== 'undefined') {
        window.headingAnchorsPlugin = headingAnchorsPlugin;
    }
    if (typeof module !== 'undefined') {
        module.exports = headingAnchorsPlugin;
    }
})();
