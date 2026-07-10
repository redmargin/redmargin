#!/bin/bash
set -e

# This script runs on the remote Linux server and executes the Linux-only test target.
# It reuses the Swift toolchain that build-remote.sh downloads into the build directory.

cd "$(dirname "$0")/../.."

SWIFT_VERSION="6.0.2"
SWIFT_PLATFORM="ubuntu22.04"
SWIFT_DIR="swift-$SWIFT_VERSION-RELEASE-$SWIFT_PLATFORM"
SWIFT_TAR="$SWIFT_DIR.tar.gz"

if [ ! -d "$SWIFT_DIR" ]; then
    echo "Downloading Swift $SWIFT_VERSION..."
    wget -q "https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2204/swift-$SWIFT_VERSION-RELEASE/$SWIFT_TAR"
    echo "Extracting..."
    tar xzf "$SWIFT_TAR"
    rm "$SWIFT_TAR"
fi

export PATH="$PWD/$SWIFT_DIR/usr/bin:$PATH"

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"

echo "Running LinuxWatcherTests..."
timeout "$TIMEOUT_SECONDS" swift test --filter LinuxWatcherTests
