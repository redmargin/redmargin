/**
 * Scroll Position Manager for RedMargin
 * Saves and restores scroll position via webkit message handlers.
 */
(function() {
    'use strict';

    let lastSavedScrollY = 0;
    let saveTimeout = null;

    function init() {
        window.addEventListener('scroll', handleScroll, { passive: true });
    }

    function handleScroll() {
        // Debounce scroll saving - save after 200ms of no scrolling
        if (saveTimeout) {
            clearTimeout(saveTimeout);
        }
        saveTimeout = setTimeout(saveScrollPosition, 200);
    }

    function saveScrollPosition() {
        const scrollY = window.scrollY;
        if (scrollY !== lastSavedScrollY) {
            lastSavedScrollY = scrollY;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollPosition) {
                window.webkit.messageHandlers.scrollPosition.postMessage({
                    scrollY: scrollY
                });
            }
        }
    }

    function restoreScrollPosition(scrollY) {
        if (typeof scrollY === 'number' && scrollY > 0) {
            // Use setTimeout to ensure DOM is fully rendered
            setTimeout(function() {
                window.scrollTo(0, scrollY);
                lastSavedScrollY = scrollY;
            }, 50);
        }
    }

    // Export for use by Swift
    window.ScrollPosition = {
        save: saveScrollPosition,
        restore: restoreScrollPosition
    };

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
