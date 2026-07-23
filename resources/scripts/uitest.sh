#!/bin/bash

# UI Test Runner for Redmargin
# Usage:
#   resources/scripts/uitest.sh                              # Run all UI tests
#   resources/scripts/uitest.sh TestClass/testMethod         # Run specific test

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
XCODEPROJ="$PROJECT_DIR/Tests/UITests/RedmarginUITests/RedmarginUITests.xcodeproj"

# Test directory setup in home
TEST_DIR="$HOME/RedmarginUITests-Temp"
DOWNLOADS_DIR="$HOME/Downloads"

# Build app first. The unit suites are not re-run here; this script runs the UI tests.
echo "Building Redmargin..."
"$SCRIPT_DIR/build.sh" --no-test

echo ""
echo "Setting up test directory..."

# Clean up test directory and any previous test PDFs
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
rm -f "$DOWNLOADS_DIR"/test*.pdf

# Create a test markdown file (long enough for multiple pages)
cat > "$TEST_DIR/test.md" << 'MARKDOWN'
# Test Document

This is a test document for PDF export testing.

## Code Block

```python
def hello():
    print("Hello, World!")
```

## Table

| Name | Value |
|------|-------|
| One  | 1     |
| Two  | 2     |

## Quote

> This is a blockquote.

## Long Content Section

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

### Subsection A

More content here to fill out the page. This ensures we have enough content to span multiple pages and verify that the fix works on all pages, not just the first one.

- Item 1 with some additional text to make it longer
- Item 2 with more content
- Item 3 continues the pattern
- Item 4 even more
- Item 5 keeps going

### Subsection B

Another block of text to ensure we have multiple pages.

| Column A | Column B | Column C |
|----------|----------|----------|
| Data 1   | Data 2   | Data 3   |
| Data 4   | Data 5   | Data 6   |
| Data 7   | Data 8   | Data 9   |

```javascript
function test() {
    console.log("Testing multi-page PDF export");
    return {
        success: true,
        pages: "multiple"
    };
}
```

### Final Section

End of document - page 2 content.
MARKDOWN

echo "Running UI tests..."

# Prompt sentry (ported from the Detours qualification runner): an independent
# process that watches for TCC "Allow" dialogs and kills this run loudly
# instead of letting xcodebuild stall behind an invisible prompt.
EVIDENCE_DIR="$PROJECT_DIR/.build/uitest/guard-$(date +%Y%m%d-%H%M%S)-$$"
GUARD_PID=""
RUN_STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"

# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
    rm -rf "$TEST_DIR"
    if [ -n "$GUARD_PID" ] && kill -0 "$GUARD_PID" 2>/dev/null; then
        kill -TERM "$GUARD_PID" 2>/dev/null || true
        wait "$GUARD_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

"$SCRIPT_DIR/uitest-prompt-guard.sh" live $$ "$PROJECT_DIR" "$EVIDENCE_DIR" &
GUARD_PID=$!
for _ in $(seq 1 50); do
    [ -f "$EVIDENCE_DIR/ready.env" ] && break
    if ! kill -0 "$GUARD_PID" 2>/dev/null; then
        echo "Error: prompt guard failed to arm (see $EVIDENCE_DIR)" >&2
        exit 91
    fi
    sleep 0.1
done
if [ ! -f "$EVIDENCE_DIR/ready.env" ]; then
    echo "Error: prompt guard never became ready (see $EVIDENCE_DIR)" >&2
    exit 91
fi
echo "Prompt guard armed (evidence: $EVIDENCE_DIR)"

# Hard deadline for the whole xcodebuild run: kill the entire process tree
# rather than hang. 30 minutes covers a cold runner rebuild with margin.
DEADLINE_EPOCH=$(( $(date +%s) + 1800 ))

TEST_RESULT=0
if [ -n "${1:-}" ]; then
    "$SCRIPT_DIR/uitest-deadline.sh" "$DEADLINE_EPOCH" xcodebuild test \
        -project "$XCODEPROJ" \
        -scheme RedmarginUITests \
        -destination 'platform=macOS' \
        -only-testing:"RedmarginUITests/$1" || TEST_RESULT=$?
else
    "$SCRIPT_DIR/uitest-deadline.sh" "$DEADLINE_EPOCH" xcodebuild test \
        -project "$XCODEPROJ" \
        -scheme RedmarginUITests \
        -destination 'platform=macOS' || TEST_RESULT=$?
fi

# A guard incident overrides the xcodebuild result: a run that "passed" while
# a permission dialog was on screen is not a pass.
if [ -f "$EVIDENCE_DIR/incident.env" ]; then
    echo "PROMPT GUARD INCIDENT:" >&2
    cat "$EVIDENCE_DIR/incident.env" >&2
    exit 90
fi

# Post-run audit: sweep the system log over the run window for any tccd
# prompt activity the live channels might have missed. An unreadable log is a
# failed audit, not a clean one.
if ! /usr/bin/log show --style compact --start "$RUN_STARTED_AT" \
        --predicate 'process == "tccd" && eventMessage CONTAINS "display_prompt"' \
        > "$EVIDENCE_DIR/post-audit-raw.log" 2> "$EVIDENCE_DIR/post-audit-err.log"; then
    echo "Error: post-run prompt audit could not read the system log (see $EVIDENCE_DIR)" >&2
    exit 91
fi
if grep -F 'display_prompt: called' "$EVIDENCE_DIR/post-audit-raw.log" > "$EVIDENCE_DIR/post-audit.log"; then
    echo "PROMPT GUARD POST-AUDIT: tccd displayed a prompt during the run:" >&2
    cat "$EVIDENCE_DIR/post-audit.log" >&2
    exit 90
fi

if [ "$TEST_RESULT" -eq 124 ]; then
    echo "UI test run exceeded its 30-minute deadline and was terminated." >&2
fi

# The PDF is inspected by PDFExportUITests itself: page count, page text, and
# the brightness of the top edge in dark theme. Nothing is verified here.
exit $TEST_RESULT
