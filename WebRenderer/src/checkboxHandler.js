/**
 * Checkbox Handler for RedMargin
 * Handles task list checkbox clicks and communicates with Swift via webkit message handlers.
 * Only toggles on deliberate clicks directly on the checkbox — ignores text selection drags
 * and clicks on surrounding text.
 */
(function() {
    'use strict';

    function init() {
        // Use click instead of change to control exactly when toggles happen
        document.addEventListener('click', handleCheckboxClick, true);
    }

    function handleCheckboxClick(event) {
        const checkbox = event.target;
        if (!checkbox.classList.contains('task-list-item-checkbox')) {
            return;
        }

        // Prevent the native toggle — we'll handle it manually if appropriate
        event.preventDefault();

        // If the user was selecting text, don't toggle
        const selection = window.getSelection();
        if (selection && !selection.isCollapsed) {
            // Revert the checked state since click already toggled it
            checkbox.checked = !checkbox.checked;
            return;
        }

        // Deliberate click — toggle the checkbox
        const checked = checkbox.checked;
        var line = 0;

        // Table checkbox: find the parent <tr> with data-sourcepos
        const tableRow = checkbox.closest('tr');
        if (tableRow) {
            const sourcepos = tableRow.getAttribute('data-sourcepos');
            if (!sourcepos) return;
            const match = sourcepos.match(/^(\d+):/);
            if (!match) return;
            line = parseInt(match[1], 10);
        } else {
            // List item checkbox
            const listItem = checkbox.closest('li.task-list-item');
            if (!listItem) return;
            const sourcepos = listItem.getAttribute('data-sourcepos');
            if (!sourcepos) return;
            const match = sourcepos.match(/^(\d+):/);
            if (!match) return;
            line = parseInt(match[1], 10);
        }

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
