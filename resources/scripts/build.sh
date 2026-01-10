#!/bin/bash
set -e

cd "$(dirname "$0")/../.."

APP_NAME="RedMargin"
APP_BUNDLE_ID="com.redmargin.app"
APP_DIR="build/RedMargin.app"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "RedMargin is running; quitting before rebuild..."
    osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..50}; do
        if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "RedMargin is still running; refusing to overwrite the app bundle."
        exit 1
    fi
fi

echo "Building RedMargin..."
swift build

echo "Updating app bundle..."
cp .build/arm64-apple-macosx/debug/RedMargin build/RedMargin.app/Contents/MacOS/RedMargin

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-RedMargin Dev}"
CODESIGN_KEYCHAIN="${CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/redmargin-codesign.keychain-db}"

ENTITLEMENTS="RedMargin.entitlements"

if [ -d "$APP_DIR" ] && [ -f "$CODESIGN_KEYCHAIN" ]; then
    security unlock-keychain -p "" "$CODESIGN_KEYCHAIN" >/dev/null 2>&1 || true
    /usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS" --keychain "$CODESIGN_KEYCHAIN" -s "$CODESIGN_IDENTITY" "$APP_DIR"
    echo "Codesigned app bundle with entitlements."
else
    echo "Codesign skipped (missing app bundle or keychain)."
fi

echo "Touching app bundle to refresh Spotlight..."
touch build/RedMargin.app

if [ "$1" = "--no-install" ]; then
    echo "Done! App bundle updated at build/RedMargin.app"
else
    echo "Installing to ~/Applications..."
    mkdir -p ~/Applications
    rm -rf ~/Applications/RedMargin.app
    cp -R build/RedMargin.app ~/Applications/RedMargin.app
    echo "Done! App installed to ~/Applications/RedMargin.app"
fi
