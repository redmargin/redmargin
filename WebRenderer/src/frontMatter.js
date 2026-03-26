(function() {
    'use strict';

    var tagFields = ['tags', 'categories', 'keywords', 'labels'];
    var dateFields = ['date', 'updated', 'published', 'created', 'modified'];

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function extract(markdown) {
        if (!markdown || !markdown.startsWith('---')) {
            return { body: markdown, fields: null, lineCount: 0 };
        }

        var match = markdown.match(/^---[ \t]*\n([\s\S]*?)\n---[ \t]*(?:\n|$)/);
        if (!match) {
            return { body: markdown, fields: null, lineCount: 0 };
        }

        var yamlBlock = match[1];
        var fullMatch = match[0];
        var body = markdown.slice(fullMatch.length);
        var lineCount = fullMatch.split('\n').length - (fullMatch.endsWith('\n') ? 1 : 0);
        var fields = parseYamlSubset(yamlBlock);

        if (!fields || fields.length === 0) {
            return { body: markdown, fields: null, lineCount: 0 };
        }

        return { body: body, fields: fields, lineCount: lineCount };
    }

    function parseYamlSubset(yaml) {
        var lines = yaml.split('\n');
        var fields = [];
        var currentKey = null;
        var currentArrayItems = null;

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];

            if (/^\s*$/.test(line) || /^\s*#/.test(line)) continue;

            var arrayItemMatch = line.match(/^\s+-\s+(.*)/);
            if (arrayItemMatch && currentKey) {
                if (!currentArrayItems) currentArrayItems = [];
                currentArrayItems.push(arrayItemMatch[1].trim());
                continue;
            }

            if (currentKey && currentArrayItems) {
                fields.push({ key: currentKey, value: currentArrayItems });
                currentKey = null;
                currentArrayItems = null;
            }

            var kvMatch = line.match(/^([A-Za-z_][\w.-]*)\s*:\s*(.*)/);
            if (!kvMatch) continue;

            currentKey = kvMatch[1];
            var rawValue = kvMatch[2].trim();
            if (!rawValue) continue;

            var flowMatch = rawValue.match(/^\[(.*)\]$/);
            if (flowMatch) {
                var items = flowMatch[1].split(',').map(function(s) {
                    return s.trim().replace(/^["']|["']$/g, '');
                }).filter(Boolean);
                fields.push({ key: currentKey, value: items });
                currentKey = null;
                continue;
            }

            fields.push({
                key: currentKey,
                value: rawValue.replace(/^["']|["']$/g, '')
            });
            currentKey = null;
        }

        if (currentKey && currentArrayItems) {
            fields.push({ key: currentKey, value: currentArrayItems });
        } else if (currentKey) {
            fields.push({ key: currentKey, value: '' });
        }

        return fields;
    }

    function formatDate(str) {
        var date = new Date(str);
        if (isNaN(date.getTime())) return escapeHtml(str);

        try {
            return new Intl.DateTimeFormat(undefined, {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            }).format(date);
        } catch (error) {
            return escapeHtml(str);
        }
    }

    function renderCard(fields) {
        var rows = '';

        for (var i = 0; i < fields.length; i++) {
            var field = fields[i];
            var key = field.key;
            var value = field.value;
            var valueHtml;

            if (Array.isArray(value) && tagFields.indexOf(key.toLowerCase()) !== -1) {
                valueHtml = '<ul class="fm-tag-list">' + value.map(function(tag) {
                    return '<li class="fm-tag">' + escapeHtml(tag) + '</li>';
                }).join('') + '</ul>';
            } else if (Array.isArray(value)) {
                valueHtml = escapeHtml(value.join(', '));
            } else if (key.toLowerCase() === 'draft' && (value === 'true' || value === true)) {
                valueHtml = '<span class="fm-badge-draft">Draft</span>';
            } else if (dateFields.indexOf(key.toLowerCase()) !== -1) {
                valueHtml = formatDate(value);
            } else {
                valueHtml = escapeHtml(value);
            }

            rows += '<div class="fm-row"><dt class="fm-label">' +
                escapeHtml(key) + '</dt><dd class="fm-value">' +
                valueHtml + '</dd></div>';
        }

        return '<section id="front-matter" role="region" aria-label="Document metadata">' +
            '<dl class="fm-fields">' + rows + '</dl></section>';
    }

    window.FrontMatter = {
        extract: extract,
        renderCard: renderCard
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = window.FrontMatter;
    }
})();
