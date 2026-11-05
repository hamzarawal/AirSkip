#!/bin/bash
set -euo pipefail
AIRSKIP_TARGET=${1:?Usage: sign-app.sh path/to/AirSkip.app}
AIRSKIP_IDENTITY=${AIRSKIP_SIGN_IDENTITY:-}

if [[ -z "$AIRSKIP_IDENTITY" ]]; then
  AIRSKIP_IDENTITIES=$(security find-identity -v -p codesigning)
  AIRSKIP_CANDIDATES=$(printf '%s\n' "$AIRSKIP_IDENTITIES" | /usr/bin/sed -nE \
    's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) "(Apple Development:|Developer ID Application:|Mac Developer:).*$/\1/p')
  AIRSKIP_COUNT=$(printf '%s\n' "$AIRSKIP_CANDIDATES" | /usr/bin/awk 'NF { n++ } END { print n+0 }')
  case "$AIRSKIP_COUNT" in
    0) AIRSKIP_IDENTITY=- ;;
    1) AIRSKIP_IDENTITY="$AIRSKIP_CANDIDATES" ;;
    *)
      printf 'Multiple signing certificates found. Set AIRSKIP_SIGN_IDENTITY to a certificate SHA-1 from security find-identity -v -p codesigning, or to - for a local ad hoc build.\n' >&2
      exit 1
      ;;
  esac
fi

if [[ "$AIRSKIP_IDENTITY" == '-' ]]; then
  printf 'Signing for local use. A changed build may need Accessibility permission granted again.\n'
fi
codesign --force --sign "$AIRSKIP_IDENTITY" --timestamp=none \
  --identifier local.airskip.app "$AIRSKIP_TARGET"
codesign --verify --strict "$AIRSKIP_TARGET"
