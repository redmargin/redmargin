#!/bin/bash
set -e

# Runs the XCUITest suite on the Foundry Mac build host.
#
# XCUITest drives the real UI: it takes over the screen, installs the app into
# /Applications, and needs an unlocked signing keychain. It is NEVER run on Spectre.
# Foundry is provisioned for it (Automation Mode without authentication, a no-timeout
# login keychain, and a self-unlock password file), so an SSH-driven run raises no prompts.
#
# Usage:
#   resources/scripts/uitest-foundry.sh                       # all UI tests
#   resources/scripts/uitest-foundry.sh PDFExportUITests/testX # one test

REMOTE_HOST="foundry"
REMOTE_DIR="dev/redmargin"
# Foundry signs with the Developer ID identity; "Detour Dev" is Spectre's local cert.
REMOTE_IDENTITY="Developer ID Application: Marco Fruh (AHUQTWVD7X)"

cd "$(dirname "$0")/../.."

echo "Step 1: Syncing source to $REMOTE_HOST..."
# Keep the remote build cache; only the working tree is mirrored.
rsync -az --delete \
    --exclude '.git' \
    --exclude '.build' \
    --exclude 'build' \
    --exclude 'node_modules' \
    --exclude '.DS_Store' \
    --exclude '*.dmg' \
    ./ "$REMOTE_HOST:$REMOTE_DIR/"

echo "Step 2: Running UI tests on $REMOTE_HOST..."
TEST_RESULT=0
# shellcheck disable=SC2029  # REMOTE_DIR, the identity, and the filter are ours and expand here
ssh "$REMOTE_HOST" \
    "cd $REMOTE_DIR && CODESIGN_IDENTITY='$REMOTE_IDENTITY' bash resources/scripts/uitest.sh ${1:-}" \
    || TEST_RESULT=$?

exit $TEST_RESULT
