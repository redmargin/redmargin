#!/bin/bash
set -e

# This script builds the redmargin-server binary for Linux x86_64
# by syncing source to the 'devtest' server and running the build there.

REMOTE_HOST="devtest"
REMOTE_DIR="~/redmargin-build"
LOCAL_BINARY="resources/servers/redmargin-server-x86_64-linux"

echo "Step 1: Syncing source to $REMOTE_HOST..."
ssh $REMOTE_HOST "mkdir -p $REMOTE_DIR"
rsync -avz --delete \
    --exclude '.build' \
    --exclude '.git' \
    --exclude '*.artifactbundle.tar.gz' \
    --exclude 'resources/icons' \
    --exclude 'build' \
    . $REMOTE_HOST:$REMOTE_DIR/

echo "Step 2: Building on $REMOTE_HOST..."
ssh $REMOTE_HOST "bash $REMOTE_DIR/resources/scripts/build-remote.sh"

echo "Step 3: Fetching binary back..."
mkdir -p resources/servers
scp $REMOTE_HOST:$REMOTE_DIR/.build/release/redmargin-server $LOCAL_BINARY

echo "Done! Binary saved to $LOCAL_BINARY"
ls -lh $LOCAL_BINARY
