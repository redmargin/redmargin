import Foundation

/// Toggles the first `[ ]` or `[x]`/`[X]` checkbox on a line of markdown text.
/// Works for both list items (`- [ ]`) and table cells (`| [ ] |`).
/// Returns the original line unchanged if no checkbox pattern is found.
public func toggleCheckbox(in line: String, checked: Bool) -> String {
    if checked {
        // Replace first unchecked checkbox with checked
        if let range = line.range(of: "[ ]") {
            var result = line
            result.replaceSubrange(range, with: "[x]")
            return result
        }
    } else {
        // Replace first checked checkbox with unchecked
        if let range = line.range(of: "[x]", options: .caseInsensitive) {
            var result = line
            result.replaceSubrange(range, with: "[ ]")
            return result
        }
    }
    return line
}
