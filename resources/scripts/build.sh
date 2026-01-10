#!/bin/bash
set -e

cd "$(dirname "$0")/../.."

APP_NAME="Redmargin"
APP_BUNDLE_ID="com.redmargin.app"
APP_DIR="build/Redmargin.app"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Redmargin is running; quitting before rebuild..."
    osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..50}; do
        if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "Redmargin is still running; refusing to overwrite the app bundle."
        exit 1
    fi
fi

echo "Building Redmargin..."
swift build -c release

echo "Creating app bundle..."
rm -rf build/Redmargin.app
mkdir -p build/Redmargin.app/Contents/MacOS
mkdir -p build/Redmargin.app/Contents/Resources
cp .build/arm64-apple-macosx/release/Redmargin build/Redmargin.app/Contents/MacOS/Redmargin
cp build/Info.plist build/Redmargin.app/Contents/
cp build/PkgInfo build/Redmargin.app/Contents/

echo "Bundling WebRenderer assets..."
RESOURCES_DIR="build/Redmargin.app/Contents/Resources"
rm -rf "$RESOURCES_DIR/WebRenderer"
mkdir -p "$RESOURCES_DIR/WebRenderer/src/vendor" "$RESOURCES_DIR/WebRenderer/styles"
cp WebRenderer/src/renderer.html "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/index.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/sourcepos.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/checkboxHandler.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/lineNumbers.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/scrollPosition.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/vendor/*.js "$RESOURCES_DIR/WebRenderer/src/vendor/"
cp WebRenderer/styles/*.css "$RESOURCES_DIR/WebRenderer/styles/"

echo "Bundling app icon..."
cp resources/Redmargin.icns "$RESOURCES_DIR/"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "build/Redmargin.app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Redmargin" "build/Redmargin.app/Contents/Info.plist"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-RedMargin Dev}"
CODESIGN_KEYCHAIN="${CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/redmargin-codesign.keychain-db}"

ENTITLEMENTS="Redmargin.entitlements"

if [ -d "$APP_DIR" ] && [ -f "$CODESIGN_KEYCHAIN" ]; then
    security unlock-keychain -p "" "$CODESIGN_KEYCHAIN" >/dev/null 2>&1 || true
    /usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS" --keychain "$CODESIGN_KEYCHAIN" -s "$CODESIGN_IDENTITY" "$APP_DIR"
    echo "Codesigned app bundle with entitlements."
else
    echo "Codesign skipped (missing app bundle or keychain)."
fi

echo "Touching app bundle to refresh Spotlight..."
touch build/Redmargin.app

echo "Installing to /Applications..."
rm -rf /Applications/Redmargin.app 2>/dev/null || true
mv build/Redmargin.app /Applications/

echo "Done!"
