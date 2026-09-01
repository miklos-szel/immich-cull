#!/bin/bash
# Builds an UNSIGNED .ipa of ImmichCull for distribution through the SideStore source.
#
# Usage: ./scripts/build-unsigned-ipa.sh
#
# Output: build/ImmichCull-unsigned.ipa
#
# This is deliberately NOT build-ipa.sh. That script signs with a development
# profile for installing on the maintainer's own device, and the resulting .ipa
# embeds embedded.mobileprovision — which carries the Apple team ID and the UDID
# of every registered device. Never publish that one. SideStore re-signs with the
# installing user's own Apple ID, so what we ship is unsigned.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/ImmichCull-unsigned.xcarchive"
APP_NAME="ImmichCull.app"
IPA_PATH="$BUILD_DIR/ImmichCull-unsigned.ipa"

if command -v xcodegen >/dev/null; then
    xcodegen generate
elif [ ! -d ImmichCull.xcodeproj ]; then
    echo "error: ImmichCull.xcodeproj missing and xcodegen not installed (brew install xcodegen)" >&2
    exit 1
fi

rm -rf "$ARCHIVE_PATH" "$BUILD_DIR/Payload" "$IPA_PATH"

# project.yml sets CODE_SIGN_IDENTITY / CODE_SIGNING_ALLOWED in settings.base, so
# all three overrides are needed on the command line to actually disable signing.
xcodebuild -project ImmichCull.xcodeproj -scheme ImmichCull \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    archive

# Packaged by hand: -exportArchive insists on a signing method.
mkdir -p "$BUILD_DIR/Payload"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$BUILD_DIR/Payload/"

# An unsigned archive should contain neither of these; removing them anyway is
# the whole point of this script.
rm -rf "$BUILD_DIR/Payload/$APP_NAME/_CodeSignature" \
       "$BUILD_DIR/Payload/$APP_NAME/embedded.mobileprovision"

(cd "$BUILD_DIR" && zip -qry "$(basename "$IPA_PATH")" Payload)

if unzip -l "$IPA_PATH" | grep -Eiq 'embedded\.mobileprovision|_CodeSignature'; then
    echo "error: $IPA_PATH still contains signing material — do not publish it" >&2
    exit 1
fi

SIZE=$(stat -f%z "$IPA_PATH")
SHA=$(shasum -a 256 "$IPA_PATH" | cut -d' ' -f1)

echo
echo "Done: $IPA_PATH"
echo "  size:   $SIZE bytes"
echo "  sha256: $SHA"
