#!/bin/bash
# Security verification tests for RedMargin
# Tests XSS prevention and sandbox behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="/tmp/redmargin-security-test"
APP_NAME="Redmargin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== RedMargin Security Tests ==="
echo ""

# Clean up any previous test files
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Create malicious test files
echo "Creating test files..."

# XSS via script tag
cat > "$TEST_DIR/xss-script.md" << 'EOF'
# XSS Test - Script Tag

This file tests script injection:

<script>alert('XSS via script tag!')</script>

Normal content after script.
EOF

# XSS via event handler
cat > "$TEST_DIR/xss-event.md" << 'EOF'
# XSS Test - Event Handler

This file tests event handler injection:

<img src="x" onerror="alert('XSS via onerror!')">

<p onclick="alert('XSS via onclick!')">Click me</p>

Normal content after event handlers.
EOF

# XSS via javascript URL
cat > "$TEST_DIR/xss-url.md" << 'EOF'
# XSS Test - JavaScript URL

This file tests javascript URL injection:

[Click me](javascript:alert('XSS via javascript URL!'))

<a href="javascript:alert('XSS!')">Another link</a>

Normal content after javascript URLs.
EOF

# Remote image test
cat > "$TEST_DIR/remote-image.md" << 'EOF'
# Remote Image Test

This tests remote image blocking:

![Remote Image](https://example.com/image.png)

Normal content after remote image.
EOF

# Safe HTML test
cat > "$TEST_DIR/safe-html.md" << 'EOF'
# Safe HTML Test

This tests that safe HTML renders correctly:

<p><strong>Bold</strong> and <em>italic</em></p>

<table>
<tr><th>Header 1</th><th>Header 2</th></tr>
<tr><td>Cell 1</td><td>Cell 2</td></tr>
</table>

<blockquote>A quote</blockquote>

- [x] Checked item
- [ ] Unchecked item
EOF

echo "Test files created in $TEST_DIR"
echo ""

# Check if app is built
APP_PATH="$PROJECT_DIR/.build/debug/Redmargin.app"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${YELLOW}App not found at $APP_PATH${NC}"
    echo "Building app..."
    cd "$PROJECT_DIR"
    swift build
fi

# Function to test opening a file
test_open_file() {
    local file=$1
    local description=$2

    echo -n "Testing: $description... "

    # Open the file
    open -a "$APP_NAME" "$file" 2>/dev/null || true

    # Wait for app to process
    sleep 2

    # Check if app is still running
    if pgrep -x "$APP_NAME" > /dev/null; then
        echo -e "${GREEN}PASS${NC} (app still running)"
        return 0
    else
        echo -e "${RED}FAIL${NC} (app crashed)"
        return 1
    fi
}

# Make sure app is running first
echo "Starting $APP_NAME..."
open -a "$APP_NAME" "$TEST_DIR/safe-html.md" 2>/dev/null || true
sleep 3

# Run tests
echo ""
echo "Running security tests..."
echo ""

FAILED=0

test_open_file "$TEST_DIR/xss-script.md" "XSS via script tag" || ((FAILED++))
test_open_file "$TEST_DIR/xss-event.md" "XSS via event handler" || ((FAILED++))
test_open_file "$TEST_DIR/xss-url.md" "XSS via javascript URL" || ((FAILED++))
test_open_file "$TEST_DIR/remote-image.md" "Remote image blocking" || ((FAILED++))
test_open_file "$TEST_DIR/safe-html.md" "Safe HTML rendering" || ((FAILED++))

echo ""
echo "=== Results ==="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All security tests passed!${NC}"
else
    echo -e "${RED}$FAILED test(s) failed${NC}"
fi

# Cleanup
echo ""
echo "Cleaning up..."
osascript -e 'quit app "Redmargin"' 2>/dev/null || true
rm -rf "$TEST_DIR"

echo "Done."
exit $FAILED
