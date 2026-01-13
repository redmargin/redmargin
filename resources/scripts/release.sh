#!/bin/bash
set -euo pipefail

# Release script for Redmargin
# Usage: ./resources/scripts/release.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERSION=$(grep -A1 'CFBundleShortVersionString' "$PROJECT_DIR/build/Info.plist" | grep string | sed 's/.*<string>\(.*\)<\/string>/\1/')

if [[ -z "$VERSION" ]]; then
    echo "Error: Could not extract version from Info.plist"
    exit 1
fi

echo "Version: $VERSION"
APP_PATH="$PROJECT_DIR/build/Redmargin.app"
DMG_NAME="Redmargin-$VERSION.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
STAGING_DIR="$PROJECT_DIR/.build/dmg-staging"

cd "$PROJECT_DIR"

echo "==> Building release..."
CODESIGN_IDENTITY="Developer ID Application: Marco Fruh (AHUQTWVD7X)" \
CODESIGN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db" \
"$SCRIPT_DIR/build.sh" --no-install

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: Build failed, no app at $APP_PATH"
    exit 1
fi

echo "==> Creating DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "Redmargin" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo "==> Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "redmargin-notarize" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "Release prepared: $DMG_PATH"
echo ""
echo "Next steps:"
echo "  1. Test the DMG"
echo "  2. Tag and push to trigger release workflow:"
echo ""
echo "     git tag v$VERSION && git push public v$VERSION"
echo ""
echo "  3. Upload DMG to the release:"
echo ""
echo "     gh release upload v$VERSION \"$DMG_NAME\" --repo redmargin/redmargin"
