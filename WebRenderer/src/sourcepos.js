/**
 * markdown-it plugin that adds data-sourcepos attributes to block elements.
 * Uses token.map which provides [startLine, endLine] (0-indexed).
 * Output format: data-sourcepos="startLine:0-endLine:0"
 * Lines are converted to 1-indexed for consistency with editors.
 */
function sourceposPlugin(md) {
    const blockTokens = [
        'paragraph_open',
        'heading_open',
        'bullet_list_open',
        'ordered_list_open',
        'list_item_open',
        'blockquote_open',
        'code_block',
        'fence',
        'table_open',
        'hr'
    ];

    function addSourcepos(tokens, idx) {
        const token = tokens[idx];
        if (token.map && blockTokens.includes(token.type)) {
            const startLine = token.map[0] + 1;
            const endLine = token.map[1];
            token.attrSet('data-sourcepos', `${startLine}:0-${endLine}:0`);
        }
    }

    md.core.ruler.push('sourcepos', function(state) {
        state.tokens.forEach((token, idx) => {
            addSourcepos(state.tokens, idx);
            if (token.children) {
                token.children.forEach((child, childIdx) => {
                    addSourcepos(token.children, childIdx);
                });
            }
        });
    });
}

if (typeof window !== 'undefined') {
    window.sourceposPlugin = sourceposPlugin;
}
if (typeof module !== 'undefined') {
    module.exports = sourceposPlugin;
}
