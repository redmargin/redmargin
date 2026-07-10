#!/bin/bash
set -e

# Runs the Linux-only test target (LinuxServerTests) on the 'devtest' server.
#
# These tests compile only under `#if os(Linux)` (see Package.swift), so nothing on the
# Mac can run them. They exercise the inotify-backed watcher used by the remote helper.
#
# They start real watcher processes, so the run is bounded by a timeout.

REMOTE_HOST="devtest"
# Relative to the remote account's home directory, which is where ssh and rsync land.
REMOTE_DIR="redmargin-build"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"

cd "$(dirname "$0")/../.."

echo "Step 1: Syncing source to $REMOTE_HOST..."
# shellcheck disable=SC2029  # REMOTE_DIR is ours, and is meant to expand here
ssh "$REMOTE_HOST" "mkdir -p $REMOTE_DIR"
rsync -avz --delete \
    --exclude '.build' \
    --exclude '.git' \
    --exclude '*.artifactbundle.tar.gz' \
    --exclude 'resources/icons' \
    --exclude 'build' \
    . "$REMOTE_HOST:$REMOTE_DIR/"

echo "Step 2: Running LinuxServerTests on $REMOTE_HOST (timeout ${TIMEOUT_SECONDS}s)..."
TEST_RESULT=0
# shellcheck disable=SC2029  # both values are ours, and are meant to expand here
ssh "$REMOTE_HOST" "TIMEOUT_SECONDS=${TIMEOUT_SECONDS} bash $REMOTE_DIR/resources/scripts/test-remote.sh" || TEST_RESULT=$?

echo "Step 3: Stopping any helper left behind..."
# The bracket keeps the pattern from matching this very command line, which otherwise
# contains the literal string and makes pkill kill the shell running it.
ssh "$REMOTE_HOST" "pkill -f '[r]edmargin-server' >/dev/null 2>&1 || true"

exit $TEST_RESULT
