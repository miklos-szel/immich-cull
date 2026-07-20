#!/usr/bin/env bash
# Runs RealServerSmokeTests against the Immich instance configured in
# .secrets/immich-test.env (gitignored).
#
# xcodebuild only forwards environment variables into the app under test when
# they carry the TEST_RUNNER_ prefix, which it strips on the way in — so the
# tests read plain REAL_SERVER_URL / REAL_SERVER_API_KEY.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.secrets/immich-test.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE — see the .secrets section of CLAUDE.md." >&2
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${REAL_SERVER_URL:?not set in $ENV_FILE}"
: "${REAL_SERVER_API_KEY:?not set in $ENV_FILE}"

export TEST_RUNNER_REAL_SERVER_URL="$REAL_SERVER_URL"
export TEST_RUNNER_REAL_SERVER_API_KEY="$REAL_SERVER_API_KEY"

exec xcodebuild test \
    -project "$REPO_ROOT/ImmichCull.xcodeproj" \
    -scheme ImmichCull \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:ImmichCullUITests/RealServerSmokeTests \
    "$@"
