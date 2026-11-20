#!/bin/bash
# The dev loop. bash scripts/dev.sh: debug build, then update /Applications/Pointroo.app in place and relaunch it.
# bash scripts/dev.sh --watch: stays running and does the same whenever a file under Sources/ or Resources/ changes.
# Ctrl+C stops it. First run scripts/dev-cert.sh once, so permissions survive rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

APP="/Applications/Pointroo.app"

update_and_relaunch() {
  swift build || { echo "build failed; the running app was left alone" >&2; return 1; }
  refuse_while_recording || return 1
  resolve_codesign_identity
  cp .build/debug/PointAndYap "$APP/Contents/MacOS/Pointroo" || return 1
  cp Resources/Info.plist "$APP/Contents/Info.plist" || return 1
  rm -rf "$APP/Contents/Resources/skill"
  cp -R Resources/skill "$APP/Contents/Resources/" || return 1
  codesign --force ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} --sign "$CODESIGN_IDENTITY" \
    --entitlements Resources/PointAndYap.entitlements "$APP" || return 1
  if pgrep -x Pointroo >/dev/null; then pkill -x Pointroo; sleep 1; fi
  open "$APP"
  echo "updated and relaunched $APP"
}

run_once() {
  if [ ! -d "$APP" ]; then
    echo "$APP does not exist yet; running build.sh once"
    bash scripts/build.sh
    return
  fi
  update_and_relaunch
}

if [ "${1:-}" != "--watch" ]; then
  run_once
  exit 0
fi

stamp=$(mktemp)
trap 'rm -f "$stamp"; exit 0' INT TERM EXIT
touch "$stamp"
run_once || echo "waiting for the next change..."
echo "watching Sources/ and Resources/ (Ctrl+C to stop)"
while true; do
  sleep 1
  changed=$(find Sources Resources -type f -newer "$stamp" 2>/dev/null | head -1)
  if [ -n "$changed" ]; then
    touch "$stamp"
    echo "changed: $changed"
    run_once || echo "waiting for the next change..."
  fi
done
