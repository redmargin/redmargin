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

    function getDepth(element) {
        var depth = 0;
        var current = element;

        while (current && current.parentElement) {
            depth += 1;
            current = current.parentElement;
        }

        return depth;
    }

    function isMoreSpecific(candidate, currentBest) {
        if (!currentBest) return true;

        var candidateSpan = candidate.end - candidate.start;
        var bestSpan = currentBest.end - currentBest.start;
        if (candidateSpan !== bestSpan) {
            return candidateSpan < bestSpan;
        }

        if (candidate.depth !== currentBest.depth) {
            return candidate.depth > currentBest.depth;
        }

        if (candidate.start !== currentBest.start) {
            return candidate.start > currentBest.start;
        }

        return candidate.end < currentBest.end;
    }

    function pushUnique(results, entry) {
        if (!entry) return;

        for (var i = 0; i < results.length; i++) {
            if (results[i] === entry) {
                return;
            }
        }

        results.push(entry);
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
                    end: range.end,
                    depth: getDepth(el)
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

        for (var line = start; line <= end; line++) {
            var best = null;

            for (var i = 0; i < this.entries.length; i++) {
                var entry = this.entries[i];

                // Early exit: if entry starts after the current line, no more matches
                if (entry.start > line) break;

                if (rangesOverlap(entry.start, entry.end, line, line) &&
                    isMoreSpecific(entry, best)) {
                    best = entry;
                }
            }

            pushUnique(results, best);
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
        var candidates = [];
        var earliestStart = null;

        for (var i = 0; i < this.entries.length; i++) {
            var entry = this.entries[i];
            if (entry.start < line) {
                continue;
            }

            if (earliestStart === null || entry.start < earliestStart) {
                earliestStart = entry.start;
                candidates = [entry];
            } else if (entry.start === earliestStart) {
                candidates.push(entry);
            }
        }

        if (candidates.length > 0) {
            var best = null;
            for (var j = 0; j < candidates.length; j++) {
                if (isMoreSpecific(candidates[j], best)) {
                    best = candidates[j];
                }
            }
            return best;
        }

        // If no element starts at or after, return the most specific last entry
        if (this.entries.length > 0) {
            var latestStart = this.entries[this.entries.length - 1].start;
            var trailing = [];

            for (var k = this.entries.length - 1; k >= 0; k--) {
                if (this.entries[k].start !== latestStart) {
                    break;
                }
                trailing.push(this.entries[k]);
            }

            var fallback = null;
            for (var m = 0; m < trailing.length; m++) {
                if (isMoreSpecific(trailing[m], fallback)) {
                    fallback = trailing[m];
                }
            }

            return fallback;
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
