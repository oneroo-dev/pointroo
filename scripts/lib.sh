# Shared by build.sh and dev.sh (source it, do not run it).

# Sets CODESIGN_IDENTITY when it is empty: "Pointroo Dev" (made once by scripts/dev-cert.sh) if the keychain has it,
# else "-" (ad hoc). Says which one it used.
resolve_codesign_identity() {
  if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Pointroo Dev"'; then
      CODESIGN_IDENTITY="Pointroo Dev"
    else
      CODESIGN_IDENTITY="-"
    fi
  fi
  case "$CODESIGN_IDENTITY" in
    "-") echo "signing: ad hoc (permissions reset on every build; run scripts/dev-cert.sh once to fix that)" ;;
    "Pointroo Dev") echo "signing: Pointroo Dev (stable, permissions survive rebuilds)" ;;
    *) echo "signing: $CODESIGN_IDENTITY (hardened runtime)" ;;
  esac
  # Ad hoc and the dev certificate: no hardened runtime, no timestamp (library validation would refuse Sparkle, which
  # is signed by a different team). A real Developer ID gets both.
  if [ "$CODESIGN_IDENTITY" = "-" ] || [ "$CODESIGN_IDENTITY" = "Pointroo Dev" ]; then
    SIGN_OPTIONS=()
  else
    SIGN_OPTIONS=(--options runtime --timestamp)
  fi
}

# Never quit the app in the middle of a recording: the newest session has no events.json while its audio is still
# written. Returns 1 (and says so) when a recording runs.
refuse_while_recording() {
  local dir="$HOME/Pointroo/sessions" latest
  latest=$(ls -1d "$dir"/*/ 2>/dev/null | tail -1 || true)
  if [ -n "$latest" ] && [ ! -f "$latest/events.json" ] && [ -f "$latest/audio.caf" ] \
     && [ $(( $(date +%s) - $(stat -f %m "$latest/audio.caf") )) -lt 30 ]; then
    echo "Pointroo is recording; not restarting it now. Run again after Stop." >&2
    return 1
  fi
  return 0
}
