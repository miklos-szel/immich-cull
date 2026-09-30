#!/bin/bash
# Cuts a release of ImmichCull: builds the unsigned .ipa, publishes it as a
# GitHub release, and updates apps.json (the SideStore source manifest) to match.
#
# Usage: ./scripts/release.sh <version> [notes-file]
#   ./scripts/release.sh 1.0.1
#   ./scripts/release.sh 1.1 build/notes.md
#
# apps.json and the release asset must stay in sync — the manifest records the
# asset's exact byte size — so always go through this script rather than editing
# either by hand.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
NOTES_FILE="${2:-}"
if [ -z "$VERSION" ]; then
    echo "usage: $0 <version> [notes-file]" >&2
    exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "error: version '$VERSION' should look like 1.2 or 1.2.3" >&2
    exit 1
fi

REPO="miklos-szel/immich-cull"
TAG="v$VERSION"
PROJECT_YML="project.yml"
# Staged under build/release/ so it can never collide with build-ipa.sh's
# signed build/ImmichCull.ipa, which must not be published.
IPA="build/release/ImmichCull.ipa"
ASSET_NAME="ImmichCull.ipa"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET_NAME"

# --- preconditions -----------------------------------------------------------

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "error: releases are cut from main (on '$BRANCH')" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree is dirty — commit or stash first" >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "error: gh is not authenticated (gh auth login)" >&2
    exit 1
fi
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "error: release $TAG already exists — bump the version or delete it first" >&2
    exit 1
fi
# An existing tag is fine only if it already points at HEAD; silently moving a
# published tag (v1.0 is out there at an older commit) is never what we want.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    if [ "$(git rev-list -n1 "$TAG")" != "$(git rev-parse HEAD)" ]; then
        echo "error: tag $TAG exists and points at another commit" >&2
        exit 1
    fi
fi

# --- version bump ------------------------------------------------------------

# Anything between here and the commit can fail; don't leave a half-bumped
# project or a manifest pointing at an asset that was never uploaded.
restore_tracked() { git checkout -- "$PROJECT_YML" ImmichCull/Info.plist apps.json 2>/dev/null || true; }
trap restore_tracked ERR INT TERM

# The version lives in project.yml as MARKETING_VERSION / CURRENT_PROJECT_VERSION.
# Info.plist only references them: XcodeGen regenerates that file on every build,
# so a bump written there is silently thrown away.
OLD_BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\{0,1\}\([0-9][0-9]*\)"\{0,1\} *$/\1/p' "$PROJECT_YML")
if [ -z "$OLD_BUILD" ]; then
    echo "error: no CURRENT_PROJECT_VERSION in $PROJECT_YML" >&2
    exit 1
fi
NEW_BUILD=$((OLD_BUILD + 1))
sed -i '' \
    -e "s/^\( *MARKETING_VERSION: *\).*/\1\"$VERSION\"/" \
    -e "s/^\( *CURRENT_PROJECT_VERSION: *\).*/\1\"$NEW_BUILD\"/" \
    "$PROJECT_YML"
echo "==> $PROJECT_YML: version $VERSION, build $NEW_BUILD"

# --- build -------------------------------------------------------------------

./scripts/build-unsigned-ipa.sh
mkdir -p "$(dirname "$IPA")"
cp build/ImmichCull-unsigned.ipa "$IPA"

# The version has to survive xcodegen + the build, or SideStore compares the
# manifest against a differently-versioned bundle and never settles.
BUILT_PLIST="build/Payload/ImmichCull.app/Info.plist"
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILT_PLIST")
BUILT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$BUILT_PLIST")
if [ "$BUILT_VERSION" != "$VERSION" ] || [ "$BUILT_BUILD" != "$NEW_BUILD" ]; then
    echo "error: built app is $BUILT_VERSION ($BUILT_BUILD), expected $VERSION ($NEW_BUILD)" >&2
    exit 1
fi

# The one artifact that actually leaves this machine — re-check it directly.
if unzip -l "$IPA" | grep -Eiq 'embedded\.mobileprovision|_CodeSignature'; then
    echo "error: $IPA carries signing material — refusing to publish" >&2
    exit 1
fi

SIZE=$(stat -f%z "$IPA")
SHA=$(shasum -a 256 "$IPA" | cut -d' ' -f1)
DATE=$(date -u +%Y-%m-%d)

# --- release notes -----------------------------------------------------------

if [ -n "$NOTES_FILE" ]; then
    if [ ! -f "$NOTES_FILE" ]; then
        echo "error: notes file '$NOTES_FILE' not found" >&2
        exit 1
    fi
    NOTES=$(cat "$NOTES_FILE")
else
    NOTES="immich-cull $VERSION"
fi

BODY_FILE="build/release-notes-$VERSION.md"
{
    printf '%s\n\n' "$NOTES"
    printf 'Install with [SideStore](https://sidestore.io) or AltStore by adding this source:\n\n'
    printf '```\nhttps://raw.githubusercontent.com/%s/main/apps.json\n```\n\n' "$REPO"
    printf 'The `.ipa` is unsigned — your sideloader signs it with your own Apple ID.\n\n'
    printf '`sha256(%s)` = `%s`\n' "$ASSET_NAME" "$SHA"
} > "$BODY_FILE"

# --- manifest ----------------------------------------------------------------

VERSION="$VERSION" BUILD="$NEW_BUILD" DATE="$DATE" NOTES="$NOTES" \
DOWNLOAD_URL="$DOWNLOAD_URL" SIZE="$SIZE" SHA="$SHA" python3 - <<'PY'
import json, os

path = "apps.json"
with open(path) as f:
    source = json.load(f)

entry = {
    "version": os.environ["VERSION"],
    "buildVersion": os.environ["BUILD"],
    "date": os.environ["DATE"],
    "localizedDescription": os.environ["NOTES"],
    "downloadURL": os.environ["DOWNLOAD_URL"],
    "size": int(os.environ["SIZE"]),
    "sha256": os.environ["SHA"],
    "minOSVersion": "17.0",
}

app = source["apps"][0]
# Upsert, so a re-run after a failed release corrects the entry instead of
# stacking a duplicate. Newest version stays first.
versions = [v for v in app.get("versions", []) if v.get("version") != entry["version"]]
app["versions"] = [entry] + versions

with open(path, "w") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
python3 -m json.tool apps.json > /dev/null
echo "==> apps.json: $VERSION ($SIZE bytes)"

# --- publish -----------------------------------------------------------------
# Push before creating the release: gh tags the pushed commit, and the manifest
# is only reachable once raw.githubusercontent.com picks the commit up (~5 min
# of CDN cache), by which time the asset below is long since uploaded.

trap - ERR INT TERM
git add "$PROJECT_YML" ImmichCull/Info.plist apps.json
git commit -m "release: $TAG"
git tag "$TAG" 2>/dev/null || true
git push origin main
git push origin "$TAG"

gh release create "$TAG" "$IPA" \
    --repo "$REPO" \
    --title "immich-cull $VERSION" \
    --notes-file "$BODY_FILE"

echo
echo "Released $TAG"
echo "  asset:  $DOWNLOAD_URL"
echo "  source: https://raw.githubusercontent.com/$REPO/main/apps.json"
