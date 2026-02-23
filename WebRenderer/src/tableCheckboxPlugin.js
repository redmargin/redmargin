/**
 * markdown-it plugin that converts [ ] and [x] patterns in table cells
 * into interactive checkboxes, matching the task-list-item-checkbox style.
 */
function tableCheckboxPlugin(md) {
    // Match [ ] or [x] / [X] at the start of cell content (with optional whitespace)
    var checkboxPattern = /^\s*\[([ xX])\]\s*/;

    md.core.ruler.after('inline', 'table_checkbox', function(state) {
        var tokens = state.tokens;

        for (var i = 0; i < tokens.length; i++) {
            if (tokens[i].type !== 'inline') continue;

            // Check if this inline token is inside a table cell.
            // In markdown-it's token stream, the token immediately before
            // an inline token is always its container's opening tag.
            if (i === 0) continue;
            var prev = tokens[i - 1].type;
            if (prev !== 'td_open' && prev !== 'th_open') continue;

            var inline = tokens[i];
            if (!inline.children || inline.children.length === 0) continue;

            // Check the first text child for checkbox pattern
            var firstChild = inline.children[0];
            if (firstChild.type !== 'text') continue;

            var match = firstChild.content.match(checkboxPattern);
            if (!match) continue;

            var isChecked = match[1] === 'x' || match[1] === 'X';

            // Create checkbox token
            var checkboxToken = new state.Token('html_inline', '', 0);
            checkboxToken.content = '<input type="checkbox" class="task-list-item-checkbox table-checkbox"'
                + (isChecked ? ' checked="checked"' : '')
                + '>';

            // Remove the matched text from the first child
            firstChild.content = firstChild.content.substring(match[0].length);

            // Insert checkbox before the remaining text
            if (firstChild.content.length === 0) {
                // Replace the empty text node with the checkbox
                inline.children[0] = checkboxToken;
            } else {
                // Insert checkbox before the text
                inline.children.splice(0, 0, checkboxToken);
            }
        }
    });
}

if (typeof window !== 'undefined') {
    window.tableCheckboxPlugin = tableCheckboxPlugin;
}
if (typeof module !== 'undefined') {
    module.exports = tableCheckboxPlugin;
}
