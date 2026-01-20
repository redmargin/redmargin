#!/bin/bash
set -e

# Build macOS binary
echo "Building macOS server binary..."
swift build -c release --product redmargin-server
mkdir -p resources/servers
cp .build/release/redmargin-server resources/servers/redmargin-server-x86_64-darwin

# Linux build requires devtest server or matching SDK
echo "Note: Linux build currently requires remote execution on 'devtest' alias."
echo "Use the following command to build for Linux:"
echo "ssh devtest \"mkdir -p ~/redmargin-build\" && rsync -avz --exclude '.build' --exclude '.git' . devtest:~/redmargin-build/ && ssh devtest \"~/redmargin-build/build-remote.sh\""
