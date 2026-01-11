/**
 * Git Gutter - Displays change markers for modified/added/deleted lines
 */
(function() {
    'use strict';

    var sourceposMap = null;
    var addedRanges = [];
    var modifiedRanges = [];
    var deletedAnchors = [];
    var cachedElements = [];
    var rafId = null;

    /**
     * Updates the gutter with new change data.
     * @param {Object} changes - Object with addedRanges, modifiedRanges, deletedAnchors
     */
    function update(changes) {
        changes = changes || {};
        addedRanges = changes.addedRanges || [];
        modifiedRanges = changes.modifiedRanges || [];
        deletedAnchors = changes.deletedAnchors || [];

        console.log('[Gutter] update called:', addedRanges.length, 'added,',
                    modifiedRanges.length, 'modified,', deletedAnchors.length, 'deleted');

        // Build the sourcepos map
        sourceposMap = new window.SourcePosMap();
        sourceposMap.build();

        // Cache element references for scroll updates
        cacheElements();

        console.log('[Gutter] cachedElements:', cachedElements.length);

        // Render markers
        render();
    }

    /**
     * Caches element references and their associated change info.
     */
    function cacheElements() {
        cachedElements = [];

        // Process added ranges (green)
        for (var i = 0; i < addedRanges.length; i++) {
            var range = addedRanges[i];
            var elements = sourceposMap.getElementsForLineRange(range[0], range[1]);
            for (var j = 0; j < elements.length; j++) {
                cachedElements.push({
                    element: elements[j].element,
                    type: 'added'
                });
            }
        }

        // Process modified ranges (amber)
        for (var i = 0; i < modifiedRanges.length; i++) {
            var range = modifiedRanges[i];
            var elements = sourceposMap.getElementsForLineRange(range[0], range[1]);
            for (var j = 0; j < elements.length; j++) {
                cachedElements.push({
                    element: elements[j].element,
                    type: 'modified'
                });
            }
        }

        // Process deleted anchors (red)
        for (var k = 0; k < deletedAnchors.length; k++) {
            var anchor = deletedAnchors[k];
            var entry = sourceposMap.getElementAtOrAfterLine(anchor);

            if (entry) {
                cachedElements.push({
                    element: entry.element,
                    type: 'deleted',
                    anchorLine: anchor
                });
            }
        }
    }

    /**
     * Renders all gutter markers based on cached elements.
     */
    function render() {
        var container = document.getElementById('git-gutter');
        var gutterContainer = document.getElementById('gutter-container');

        if (!container || !gutterContainer) return;

        // Clear existing markers
        container.innerHTML = '';

        if (cachedElements.length === 0) return;

        var gutterRect = gutterContainer.getBoundingClientRect();
        var fragment = document.createDocumentFragment();
        var seenPositions = {};

        for (var i = 0; i < cachedElements.length; i++) {
            var cached = cachedElements[i];
            var el = cached.element;
            var rect = el.getBoundingClientRect();

            var top = rect.top - gutterRect.top;
            var height = rect.height;

            // For deleted markers, use a small fixed size
            if (cached.type === 'deleted') {
                // Avoid duplicate deletion markers at same position
                var posKey = Math.round(top);
                if (seenPositions[posKey]) continue;
                seenPositions[posKey] = true;

                var delMarker = document.createElement('div');
                delMarker.className = 'gutter-marker gutter-marker--deleted';
                delMarker.style.top = top + 'px';
                fragment.appendChild(delMarker);
            } else {
                var marker = document.createElement('div');
                marker.className = 'gutter-marker gutter-marker--' + cached.type;
                marker.style.top = top + 'px';
                marker.style.height = height + 'px';
                fragment.appendChild(marker);
            }
        }

        container.appendChild(fragment);
    }

    /**
     * Handles scroll events - repositions markers using cached elements.
     */
    function onScroll() {
        if (rafId) return;

        rafId = requestAnimationFrame(function() {
            rafId = null;
            render();
        });
    }

    /**
     * Handles resize events - recomputes positions.
     */
    function onResize() {
        // Debounce resize
        if (window.Gutter._resizeTimeout) {
            clearTimeout(window.Gutter._resizeTimeout);
        }

        window.Gutter._resizeTimeout = setTimeout(function() {
            render();
        }, 100);
    }

    /**
     * Clears all gutter markers.
     */
    function clear() {
        var container = document.getElementById('git-gutter');
        if (container) {
            container.innerHTML = '';
        }
        cachedElements = [];
        addedRanges = [];
        modifiedRanges = [];
        deletedAnchors = [];
    }

    // Set up event listeners
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onResize);

    // Export
    window.Gutter = {
        update: update,
        render: render,
        onScroll: onScroll,
        onResize: onResize,
        clear: clear,
        _resizeTimeout: null
    };
})();
