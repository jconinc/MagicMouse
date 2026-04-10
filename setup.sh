#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MagicMouse"
BUNDLE_ID="com.local.mouseremap"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"

echo "=== $APP_NAME Build & Install ==="

# Quit if running
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Quitting $APP_NAME..."
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
    sleep 1
fi

# Pull latest
echo "Pulling latest..."
cd "$SCRIPT_DIR"
git pull --ff-only 2>/dev/null || echo "  (no remote changes or not a git repo)"

# Build
echo "Building release..."
xcodebuild -scheme "$APP_NAME" -configuration Release -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    build -quiet

# Install
echo "Installing to $INSTALL_DIR..."
rm -rf "$APP_PATH"
cp -R "build/Build/Products/Release/$APP_NAME.app" "$INSTALL_DIR/"
codesign --force --deep --sign - "$APP_PATH"
xattr -cr "$APP_PATH"

# Launch
echo "Launching $APP_NAME..."
open "$APP_PATH"

echo ""
echo "=== Done ==="
echo ""
echo "If this is a fresh build, you may need to toggle Accessibility permission:"
echo "  System Settings > Privacy & Security > Accessibility"
echo "  Toggle $APP_NAME OFF then ON"
