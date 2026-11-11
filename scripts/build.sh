#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/dist/AirSkip.app"
INSTALL=false
case "${1:-}" in
  "") ;;
  --install)
    INSTALL=true
    APP="${AIRSKIP_INSTALL_DIR:-$HOME/Applications}/AirSkip.app"
    ;;
  --help|-h)
    printf 'Usage: bash scripts/build.sh [--install]\nBuilds dist/AirSkip.app, or installs into ~/Applications with --install.\n'
    exit 0
    ;;
  *) printf 'Usage: bash scripts/build.sh [--install]\n' >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  printf 'Usage: bash scripts/build.sh [--install]\n' >&2
  exit 2
fi
if [[ "$APP" != /* ]]; then
  printf 'AIRSKIP_INSTALL_DIR must be an absolute path.\n' >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
  printf 'AirSkip requires macOS 13 or later.\n' >&2
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  printf 'Install the Xcode command-line tools first: xcode-select --install\n' >&2
  exit 1
fi
if $INSTALL && pgrep -x AirSkip >/dev/null; then
  printf 'Quit AirSkip before installing an update.\n' >&2
  exit 1
fi
for CASE_BUD_COUNT in 0 1 2; do
  for ((CASE_POSE=0; CASE_POSE<31; CASE_POSE++)); do
    printf -v CASE_FRAME 'src/animation/case-%d-%02d.png' "$CASE_BUD_COUNT" "$CASE_POSE"
    if [[ ! -s "$CASE_FRAME" ]]; then
      printf 'Missing animation frame: %s. Restore it from Git before building.\n' "$CASE_FRAME" >&2
      exit 1
    fi
  done
done

mkdir -p .build/cache .build/clang-cache dist
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --cache-path "$PWD/.build/cache"
BIN_DIR="$(swift build -c release --cache-path "$PWD/.build/cache" --show-bin-path)"
AIRSKIP_STAGE=$(mktemp -d "${TMPDIR:-/private/tmp}/airskip-build.XXXXXX")
AIRSKIP_DEST_STAGE=
cleanup() {
  if [[ -n "$AIRSKIP_DEST_STAGE" && -d "$AIRSKIP_DEST_STAGE/previous.app" && ! -e "$APP" ]]; then
    if ! mv "$AIRSKIP_DEST_STAGE/previous.app" "$APP"; then
      printf 'Previous app preserved at %s/previous.app\n' "$AIRSKIP_DEST_STAGE" >&2
      rm -rf "$AIRSKIP_STAGE"
      return 1
    fi
  fi
  rm -rf "$AIRSKIP_STAGE"
  if [[ -n "$AIRSKIP_DEST_STAGE" ]]; then rm -rf "$AIRSKIP_DEST_STAGE"; fi
}
trap cleanup EXIT
AIRSKIP_BUNDLE="$AIRSKIP_STAGE/AirSkip.app"
mkdir -p "$AIRSKIP_BUNDLE/Contents/MacOS" "$AIRSKIP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/AirSkip" "$AIRSKIP_BUNDLE/Contents/MacOS/AirSkip"
cp Info.plist "$AIRSKIP_BUNDLE/Contents/Info.plist"
cp assets/AirSkip.icns "$AIRSKIP_BUNDLE/Contents/Resources/AirSkip.icns"
cp -R "$BIN_DIR/AirSkip_MenuBarApp.bundle" "$AIRSKIP_BUNDLE/Contents/Resources/"
xattr -cr "$AIRSKIP_BUNDLE"
bash scripts/sign-app.sh "$AIRSKIP_BUNDLE"

# Copy and verify on the destination volume before replacing an existing app.
mkdir -p "$(dirname "$APP")"
if [[ -e "$APP" || -L "$APP" ]]; then
  if [[ ! -d "$APP/Contents" || -L "$APP" ]] ||
     [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)" != local.airskip.app ]]; then
    printf 'Refusing to replace an unrecognized app at %s\n' "$APP" >&2
    exit 1
  fi
fi
AIRSKIP_DEST_STAGE=$(mktemp -d "$(dirname "$APP")/.airskip-install.XXXXXX")
ditto --norsrc --noextattr "$AIRSKIP_BUNDLE" "$AIRSKIP_DEST_STAGE/AirSkip.app"
# Finder or a synced destination can attach metadata during the copy.
xattr -cr "$AIRSKIP_DEST_STAGE/AirSkip.app"
codesign --verify --strict "$AIRSKIP_DEST_STAGE/AirSkip.app"
if [[ -d "$APP" ]]; then mv "$APP" "$AIRSKIP_DEST_STAGE/previous.app"; fi
mv "$AIRSKIP_DEST_STAGE/AirSkip.app" "$APP"
printf 'Built: %s\n' "$APP"
