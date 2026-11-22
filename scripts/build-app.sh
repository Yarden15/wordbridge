#!/usr/bin/env bash
# Builds Wordbridge.app into ./build and signs it.
#
# Signing: uses $SIGN_IDENTITY if set, otherwise the first "Apple Development"
# identity in your keychain (free with any Apple ID via Xcode > Settings > Accounts).
# Falls back to ad-hoc signing, which works but makes macOS forget the
# Accessibility permission on every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
# The new SwiftPM build system fails with only Command Line Tools installed; use the classic one.
BUILD_FLAGS="${BUILD_FLAGS:---build-system native}"
swift build -c "$CONFIG" $BUILD_FLAGS
BIN_DIR="$(swift build -c "$CONFIG" $BUILD_FLAGS --show-bin-path)"

APP="build/Wordbridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Wordbridge" "$APP/Contents/MacOS/Wordbridge"
cp Support/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "warning: no signing identity found, using ad-hoc signing." >&2
  echo "         Accessibility permission will need to be re-granted after each rebuild." >&2
fi
codesign --force --options runtime --entitlements Support/Wordbridge.entitlements --sign "$IDENTITY" "$APP"
echo "Built $APP"
