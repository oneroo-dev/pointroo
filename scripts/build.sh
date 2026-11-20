#!/bin/bash
# Builds Pointroo.app and installs it to /Applications/Pointroo.app. Without CODESIGN_IDENTITY (or with "-") everything is
# signed ad hoc, without hardened runtime; with a Developer ID in CODESIGN_IDENTITY (or in the env file named by
# POINTANDYAP_ENV) it signs with hardened runtime as before. Usage: bash scripts/build.sh
# POINTANDYAP_NO_INSTALL=1 stops after signing; POINTANDYAP_VERSION sets the version.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${CODESIGN_IDENTITY:-}" ] && [ -n "${POINTANDYAP_ENV:-}" ]; then
  set -a; . "$POINTANDYAP_ENV"; set +a
fi
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c release
APP="build/Pointroo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/PointAndYap "$APP/Contents/MacOS/Pointroo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${POINTANDYAP_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$POINTANDYAP_VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$(date +%s)" "$APP/Contents/Info.plist"
fi
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"
cp -R Resources/skill "$APP/Contents/Resources/"
cp -R Resources/Sounds "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Welcome"
cp Resources/Welcome/welcome.mp4 Resources/Welcome/welcome-poster.png "$APP/Contents/Resources/Welcome/"
# Sparkle (updates), signed from the inside out as its documentation asks for apps built outside Xcode.
mkdir -p "$APP/Contents/Frameworks"
ditto .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
F="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
  # Ad hoc: hardened runtime would refuse the ad-hoc Sparkle framework (library validation).
  SIGN_OPTIONS=()
else
  SIGN_OPTIONS=(--options runtime --timestamp)
fi
sign() { codesign --force ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} --sign "$CODESIGN_IDENTITY" "$@"; }
sign "$F/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$F/XPCServices/Downloader.xpc"
sign "$F/Autoupdate"
sign "$F/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Resources/PointAndYap.entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"
[ -n "${POINTANDYAP_NO_INSTALL:-}" ] && { echo "built $APP"; exit 0; }

# Never quit the app in the middle of a recording: the newest session has no events.json while its audio is still
# written.
dir="$HOME/Pointroo/sessions"
latest=$(ls -1d "$dir"/*/ 2>/dev/null | tail -1 || true)
if [ -n "$latest" ] && [ ! -f "$latest/events.json" ] && [ -f "$latest/audio.caf" ] \
   && [ $(( $(date +%s) - $(stat -f %m "$latest/audio.caf") )) -lt 30 ]; then
  echo "Pointroo is recording; not reinstalling now. Run again after Stop." >&2; exit 1
fi
if pgrep -x Pointroo >/dev/null; then pkill -x Pointroo; sleep 1; fi
rm -rf /Applications/Pointroo.app
cp -R "$APP" /Applications/Pointroo.app
echo "installed /Applications/Pointroo.app"
