#!/bin/bash
# Builds ImmichCullMac and packages it into a distributable .dmg.
#
# Usage: ./build-dmg.sh
#   TEAM_ID=XXXXXXXXXX ./build-dmg.sh      # override the Apple Developer team
#   CONFIGURATION=Debug ./build-dmg.sh     # default is Release
#
# Output: build/ImmichCull-<version>.dmg  (drag-to-Applications layout)
#
# Note: signed with your development certificate, not notarized — it runs on
# this machine and on machines that trust the cert; other users may need to
# right-click → Open the first time. For public distribution, add a Developer
# ID identity and notarization.
set -euo pipefail
cd "$(dirname "$0")"

TEAM_ID="${TEAM_ID:-8A58JGJS35}"
CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="ImmichCullMac"
APP_NAME="ImmichCullMac"
BUILD_DIR="build"
DERIVED="$BUILD_DIR/mac"

if command -v xcodegen >/dev/null; then
    xcodegen generate
elif [ ! -d ImmichCull.xcodeproj ]; then
    echo "error: ImmichCull.xcodeproj missing and xcodegen not installed (brew install xcodegen)" >&2
    exit 1
fi

xcodebuild -project ImmichCull.xcodeproj -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates build

APP_PATH="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: built app not found at $APP_PATH" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG_PATH="$BUILD_DIR/ImmichCull-$VERSION.dmg"

# Stage a drag-to-Applications layout, then compress it into a DMG.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "immich-cull" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

echo
echo "Done: $DMG_PATH"
