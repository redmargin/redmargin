/**
 * Checkbox Handler for RedMargin
 * Handles task list checkbox clicks and communicates with Swift via webkit message handlers.
 */
(function() {
    'use strict';

    function init() {
        document.addEventListener('change', handleCheckboxChange, true);
    }

    function handleCheckboxChange(event) {
        const checkbox = event.target;
        if (!checkbox.classList.contains('task-list-item-checkbox')) {
            return;
        }

        const listItem = checkbox.closest('li.task-list-item');
        if (!listItem) {
            return;
        }

        const sourcepos = listItem.getAttribute('data-sourcepos');
        if (!sourcepos) {
            return;
        }

        // Parse sourcepos format: "startLine:startCol-endLine:endCol"
        const match = sourcepos.match(/^(\d+):/);
        if (!match) {
            return;
        }

        const line = parseInt(match[1], 10);
        const checked = checkbox.checked;

        // Send message to Swift
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.checkboxToggle) {
            window.webkit.messageHandlers.checkboxToggle.postMessage({
                line: line,
                checked: checked
            });
        }
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
