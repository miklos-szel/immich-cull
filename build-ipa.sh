#!/bin/bash
# Builds a signed development .ipa of ImmichCull.
#
# Usage: ./build-ipa.sh
#   TEAM_ID=XXXXXXXXXX ./build-ipa.sh   # override the Apple Developer team
#
# Output: build/ImmichCull.ipa
set -euo pipefail
cd "$(dirname "$0")"

TEAM_ID="${TEAM_ID:-8A58JGJS35}"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/ImmichCull.xcarchive"

if command -v xcodegen >/dev/null; then
    xcodegen generate
elif [ ! -d ImmichCull.xcodeproj ]; then
    echo "error: ImmichCull.xcodeproj missing and xcodegen not installed (brew install xcodegen)" >&2
    exit 1
fi

xcodebuild -project ImmichCull.xcodeproj -scheme ImmichCull \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates archive

cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>debugging</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$BUILD_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates

echo
echo "Done: $BUILD_DIR/ImmichCull.ipa"
