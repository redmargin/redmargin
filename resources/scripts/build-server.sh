#!/bin/bash
set -e

mkdir -p resources/servers

# Build macOS server binaries for remote Macs.
for ARCH in x86_64 arm64; do
    case "$ARCH" in
        x86_64) OUTPUT_ARCH="x86_64" ;;
        arm64) OUTPUT_ARCH="aarch64" ;;
    esac

    echo "Building macOS server binary for $ARCH..."
    swift build -c release --arch "$ARCH" --product redmargin-server
    cp ".build/$ARCH-apple-macosx/release/redmargin-server" "resources/servers/redmargin-server-$OUTPUT_ARCH-darwin"
done

# Linux build requires devtest server or matching SDK
echo "Note: Linux build currently requires remote execution on 'devtest' alias."
echo "Use the following command to build for Linux:"
echo "ssh devtest \"mkdir -p ~/redmargin-build\" && rsync -avz --exclude '.build' --exclude '.git' . devtest:~/redmargin-build/ && ssh devtest \"~/redmargin-build/build-remote.sh\""
