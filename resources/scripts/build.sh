#!/bin/bash
set -e

cd "$(dirname "$0")/../.."

NO_INSTALL=false
RUN_TESTS=true
for arg in "$@"; do
    case "$arg" in
        --no-install) NO_INSTALL=true ;;
        --no-test) RUN_TESTS=false ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

APP_NAME="Redmargin"
APP_BUNDLE_ID="com.redmargin.app"
APP_DIR="build/Redmargin.app"

server_sources_newer_than() {
    local binary="$1"
    [ -n "$(find Server src/Core -type f -name '*.swift' -newer "$binary" 2>/dev/null | head -1)" ]
}

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Redmargin is running; quitting before rebuild..."
    osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..30}; do
        if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    # Force kill if still running
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "Force killing Redmargin..."
        pkill -9 -x "$APP_NAME" 2>/dev/null || true
        sleep 0.5
    fi
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "Redmargin is still running; refusing to overwrite the app bundle."
        exit 1
    fi
fi

DARWIN_X86_BINARY="resources/servers/redmargin-server-x86_64-darwin"
DARWIN_ARM_BINARY="resources/servers/redmargin-server-aarch64-darwin"
if [ ! -f "$DARWIN_X86_BINARY" ] || [ ! -f "$DARWIN_ARM_BINARY" ]; then
    echo "macOS server binary missing; building local macOS server binaries..."
    bash resources/scripts/build-server.sh
elif server_sources_newer_than "$DARWIN_X86_BINARY" || server_sources_newer_than "$DARWIN_ARM_BINARY"; then
    echo "Server or Core sources newer than macOS server binaries; rebuilding local macOS server binaries..."
    bash resources/scripts/build-server.sh
fi

LINUX_BINARY="resources/servers/redmargin-server-x86_64-linux"
if [ ! -f "$LINUX_BINARY" ]; then
    echo "Linux server binary missing; building on devtest..."
    bash resources/scripts/build-linux.sh
elif server_sources_newer_than "$LINUX_BINARY"; then
    echo "Server or Core sources newer than Linux binary; rebuilding on devtest..."
    bash resources/scripts/build-linux.sh
fi

echo "Building Redmargin..."
swift build -c release

if [[ "$RUN_TESTS" == "true" ]]; then
    echo "Running renderer tests..."
    (
        cd WebRenderer
        [ -d node_modules ] || npm install --silent
        npm test
    )

    echo "Running Swift tests..."
    # The live remote suites drive real SSH sessions and helper daemons against
    # `devtest`. They stay opt-in, and are run separately with a timeout guard.
    swift test \
        --skip RemoteIntegrationTests \
        --skip SSHConnectionTests \
        --skip 'SSHConnectionManagerTests/testEnsureConnectedCoalescesConcurrentCallers'
fi

echo "Creating app bundle..."
rm -rf build/Redmargin.app
mkdir -p build/Redmargin.app/Contents/MacOS
mkdir -p build/Redmargin.app/Contents/Resources
cp .build/release/Redmargin build/Redmargin.app/Contents/MacOS/Redmargin
cp build/Info.plist build/Redmargin.app/Contents/
cp build/PkgInfo build/Redmargin.app/Contents/

echo "Bundling WebRenderer assets..."
RESOURCES_DIR="build/Redmargin.app/Contents/Resources"
rm -rf "$RESOURCES_DIR/WebRenderer"
mkdir -p "$RESOURCES_DIR/WebRenderer/src/vendor" "$RESOURCES_DIR/WebRenderer/styles"
cp WebRenderer/src/renderer.html "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/index.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/frontMatter.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/sourcepos.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/sourcepos-map.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/gutter.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/checkboxHandler.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/lineNumbers.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/scrollPosition.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/sanitizer.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/mermaid.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/headingAnchors.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/tableCheckboxPlugin.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/highlight.js "$RESOURCES_DIR/WebRenderer/src/"
cp WebRenderer/src/vendor/*.js "$RESOURCES_DIR/WebRenderer/src/vendor/"
cp WebRenderer/styles/*.css "$RESOURCES_DIR/WebRenderer/styles/"

echo "Bundling app icon..."
cp resources/Redmargin.icns "$RESOURCES_DIR/"

echo "Bundling server binaries..."
mkdir -p "$RESOURCES_DIR/Servers"
for SERVER_BINARY in resources/servers/redmargin-server-*-darwin resources/servers/redmargin-server-*-linux; do
    if [ -f "$SERVER_BINARY" ]; then
        cp "$SERVER_BINARY" "$RESOURCES_DIR/Servers/"
    fi
done

/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "build/Redmargin.app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Redmargin" "build/Redmargin.app/Contents/Info.plist"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Detour Dev}"
CODESIGN_KEYCHAIN="${CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/detour-codesign.keychain-db}"
ENTITLEMENTS="Redmargin.entitlements"

# A build host's signing keychain is password protected and starts locked in every fresh
# SSH session, so it cannot be unlocked with an empty password the way the local one is.
CODESIGN_KEYCHAIN_PASSWORD="${CODESIGN_KEYCHAIN_PASSWORD:-}"
CODESIGN_KEYCHAIN_PASSWORD_FILE="${CODESIGN_KEYCHAIN_PASSWORD_FILE:-}"
if [ -z "$CODESIGN_KEYCHAIN_PASSWORD" ] && [ -f "$CODESIGN_KEYCHAIN_PASSWORD_FILE" ]; then
    CODESIGN_KEYCHAIN_PASSWORD="$(cat "$CODESIGN_KEYCHAIN_PASSWORD_FILE")"
fi

if [ -d "$APP_DIR" ]; then
    if [ -f "$CODESIGN_KEYCHAIN" ]; then
        security unlock-keychain -p "$CODESIGN_KEYCHAIN_PASSWORD" "$CODESIGN_KEYCHAIN" 2>/dev/null || true
        CODESIGN_KEYCHAIN_PASSWORD=""
        /usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS" --keychain "$CODESIGN_KEYCHAIN" -s "$CODESIGN_IDENTITY" "$APP_DIR"
    else
        /usr/bin/codesign --force --options runtime --entitlements "$ENTITLEMENTS" -s "$CODESIGN_IDENTITY" "$APP_DIR"
    fi
    echo "Codesigned app bundle."
else
    echo "Codesign skipped (missing app bundle)."
fi

echo "Touching app bundle to refresh Spotlight..."
touch build/Redmargin.app

if [[ "$NO_INSTALL" == "false" ]]; then
    echo "Installing to /Applications..."
    rm -rf /Applications/Redmargin.app 2>/dev/null || true
    mv build/Redmargin.app /Applications/

    if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
        echo "Installing CLI to /usr/local/bin/redmargin..."
        install -m 0755 resources/scripts/redmargin /usr/local/bin/redmargin
    else
        echo "CLI not installed: /usr/local/bin is not writable."
        echo "Install manually with: install -m 0755 resources/scripts/redmargin /usr/local/bin/redmargin"
    fi

    echo "Launching Redmargin..."
    open -a Redmargin
fi

echo "Done!"
