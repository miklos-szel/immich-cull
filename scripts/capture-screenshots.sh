#!/usr/bin/env bash
# Regenerates the README screenshots in docs/screenshots/.
#
# Runs against the mock server, whose images are generated — no photo from a
# real Immich library is ever involved. MOCK_PHOTO_STYLE=gradient makes those
# images read as blurred photographs rather than flat colour blocks.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/docs/screenshots"
RESULT_BUNDLE="$(mktemp -d)/screenshots.xcresult"

cleanup() {
    [[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "Starting the mock server…"
MOCK_PHOTO_STYLE=gradient python3 "$REPO_ROOT/scratchpad/mock_immich.py" >/dev/null 2>&1 &
MOCK_PID=$!
for _ in {1..10}; do
    curl -sf -m 2 http://127.0.0.1:2283/api/server/ping >/dev/null && break
    sleep 1
done

echo "Running the capture test…"
# xcodebuild forwards TEST_RUNNER_-prefixed vars from its own environment into
# the test runner process, stripping the prefix. Passing them as arguments
# instead makes xcodebuild read them as build settings, and the test never
# sees them.
export TEST_RUNNER_CAPTURE_SCREENSHOTS=1
xcodebuild test \
    -project "$REPO_ROOT/ImmichCull.xcodeproj" \
    -scheme ImmichCull \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:ImmichCullUITests/ScreenshotTests \
    -resultBundlePath "$RESULT_BUNDLE"

echo "Extracting attachments…"
mkdir -p "$OUT_DIR"
xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$OUT_DIR" \
    --test-id-filter "ScreenshotTests/testCaptureReadmeScreenshots()" 2>/dev/null \
    || xcrun xcresulttool export attachments --path "$RESULT_BUNDLE" --output-path "$OUT_DIR"

# The exporter writes generated filenames plus a manifest; rename by the
# attachment name we set in the test, then halve the resolution — the
# originals are far too large to sit in a README.
python3 "$REPO_ROOT/scripts/rename_screenshots.py" "$OUT_DIR"

for f in "$OUT_DIR"/*.png; do
    sips --resampleWidth 390 "$f" >/dev/null
done

echo "Wrote $(ls "$OUT_DIR"/*.png | wc -l | tr -d ' ') screenshots to docs/screenshots/"
