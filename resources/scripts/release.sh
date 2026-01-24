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

echo "==> Generating release notes..."
CHANGELOG="$PROJECT_DIR/resources/docs/CHANGELOG.md"
RELEASE_NOTES="$PROJECT_DIR/RELEASE_NOTES.md"

# Extract latest changelog entry (first ## section after header)
LATEST_ENTRY=$(awk '/^## [0-9]/{if(found) exit; found=1} found{print}' "$CHANGELOG")
ENTRY_BODY=$(echo "$LATEST_ENTRY" | tail -n +2)

cat > "$RELEASE_NOTES" << EOF
## What's New in $VERSION

$ENTRY_BODY

---

Redmargin is a Markdown viewer for macOS with Git diff gutter, remote file support via SSH, and PDF export.

**Requirements:** macOS 14.0 (Sonoma) or later
EOF

echo "==> Tagging v$VERSION..."
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "Tag v$VERSION already exists, skipping"
else
    git tag -a "v$VERSION" -m "Version $VERSION"
fi

echo ""
echo "Release prepared: $DMG_PATH"
echo ""
read -p "Push tag and upload DMG to GitHub? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "==> Pushing tag v$VERSION..."
    git push public "v$VERSION"

    echo "==> Waiting for GitHub Actions to create release..."
    sleep 10

    echo "==> Uploading DMG..."
    gh release upload "v$VERSION" "$DMG_NAME" --repo redmargin/redmargin --clobber

    echo ""
    echo "Done! https://github.com/redmargin/redmargin/releases/tag/v$VERSION"
else
    echo "Skipped. To publish manually:"
    echo "  git push public v$VERSION"
    echo "  gh release upload v$VERSION $DMG_NAME --repo redmargin/redmargin --clobber"
fi
