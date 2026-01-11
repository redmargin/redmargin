/**
 * SourcePosMap - Maps source line numbers to DOM elements
 * Uses data-sourcepos attributes to build the mapping.
 */
(function() {
    'use strict';

    /**
     * Parses a sourcepos attribute value into start and end lines.
     * Format: "startLine:startCol-endLine:endCol"
     * @param {string} sourcepos - The sourcepos attribute value
     * @returns {{start: number, end: number}|null} - Parsed line range or null
     */
    function parseSourcepos(sourcepos) {
        if (!sourcepos) return null;

        const match = sourcepos.match(/^(\d+):\d+-(\d+):\d+$/);
        if (!match) return null;

        return {
            start: parseInt(match[1], 10),
            end: parseInt(match[2], 10)
        };
    }

    /**
     * Checks if two line ranges overlap.
     * @param {number} aStart - First range start
     * @param {number} aEnd - First range end
     * @param {number} bStart - Second range start
     * @param {number} bEnd - Second range end
     * @returns {boolean} - True if ranges overlap
     */
    function rangesOverlap(aStart, aEnd, bStart, bEnd) {
        return aStart <= bEnd && bStart <= aEnd;
    }

    /**
     * SourcePosMap class
     */
    function SourcePosMap() {
        this.entries = [];
    }

    /**
     * Builds the map by querying all elements with data-sourcepos.
     * Should be called after rendering markdown.
     */
    SourcePosMap.prototype.build = function() {
        this.entries = [];

        const content = document.getElementById('content-container');
        if (!content) return;

        const elements = content.querySelectorAll('[data-sourcepos]');

        elements.forEach(function(el) {
            const sourcepos = el.getAttribute('data-sourcepos');
            const range = parseSourcepos(sourcepos);

            if (range) {
                this.entries.push({
                    element: el,
                    start: range.start,
                    end: range.end
                });
            }
        }, this);

        // Sort by start line for efficient searching
        this.entries.sort(function(a, b) {
            return a.start - b.start;
        });
    };

    /**
     * Gets all elements whose source line range overlaps with the given range.
     * @param {number} start - Range start line (inclusive)
     * @param {number} end - Range end line (inclusive)
     * @returns {Array<{element: Element, start: number, end: number}>}
     */
    SourcePosMap.prototype.getElementsForLineRange = function(start, end) {
        var results = [];

        for (var i = 0; i < this.entries.length; i++) {
            var entry = this.entries[i];

            // Early exit: if entry starts after our range ends, no more matches
            if (entry.start > end) break;

            if (rangesOverlap(entry.start, entry.end, start, end)) {
                results.push(entry);
            }
        }

        return results;
    };

    /**
     * Gets the element at or after the given line.
     * Used for positioning deletion markers.
     * @param {number} line - The line number
     * @returns {{element: Element, start: number, end: number}|null}
     */
    SourcePosMap.prototype.getElementAtOrAfterLine = function(line) {
        // Find first element that starts at or after the line
        for (var i = 0; i < this.entries.length; i++) {
            if (this.entries[i].start >= line) {
                return this.entries[i];
            }
        }

        // If no element starts at or after, return the last element
        if (this.entries.length > 0) {
            return this.entries[this.entries.length - 1];
        }

        return null;
    };

    /**
     * Gets all entries (for testing/debugging).
     * @returns {Array<{element: Element, start: number, end: number}>}
     */
    SourcePosMap.prototype.getEntries = function() {
        return this.entries.slice();
    };

    // Export
    window.SourcePosMap = SourcePosMap;

    // Export helpers for testing
    window.SourcePosMap.parseSourcepos = parseSourcepos;
    window.SourcePosMap.rangesOverlap = rangesOverlap;
})();
