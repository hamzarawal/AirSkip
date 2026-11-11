#!/bin/bash
set -euo pipefail
AIRSKIP_TARGET=${1:?Usage: verify-app.sh path/to/AirSkip.app}

# File providers can restore FinderInfo immediately after it is removed. Verify
# a metadata-free copy outside the destination instead of racing that service.
# Signed file contents and the original signature are preserved, never re-signed.
AIRSKIP_VERIFY_STAGE=$(mktemp -d /private/tmp/airskip-verify.XXXXXX)
trap 'rm -rf "$AIRSKIP_VERIFY_STAGE"' EXIT
ditto --norsrc --noextattr "$AIRSKIP_TARGET" "$AIRSKIP_VERIFY_STAGE/AirSkip.app"
xattr -cr "$AIRSKIP_VERIFY_STAGE/AirSkip.app"
codesign --verify --strict "$AIRSKIP_VERIFY_STAGE/AirSkip.app"
