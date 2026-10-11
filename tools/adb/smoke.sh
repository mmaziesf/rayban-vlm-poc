#!/usr/bin/env bash
# Bot-run smoke test on a connected phone/emulator (debug APK, Mock Device Kit). No human needed.
#   tools/adb/smoke.sh [text] [--via-mock-speech]
# Launches the app, waits for the mock loop, fires a turn via the debug broadcast, and asserts the
# GlanceHud logcat sequence ends in Answer/Logged. Exit 0 = pass.
set -euo pipefail
source "$(dirname "$0")/../env.sh" >/dev/null
ADB="$ANDROID_HOME/platform-tools/adb ${ANDROID_SERIAL:+-s $ANDROID_SERIAL}"; PKG=dev.arash.glance
SLOW=${SMOKE_SLOW:-1}   # wait multiplier: 1 = phone, 6 = TCG emulator on the box
TEXT="${1:-what am I seeing}"; VIA=false; [[ "${2:-}" == "--via-mock-speech" ]] && VIA=true
$ADB shell am force-stop $PKG   # fresh process each run, so "Loop running" is logged again
$ADB logcat -c
$ADB shell am start -W -n $PKG/glance.app.MainActivity >/dev/null
for i in $(seq 1 $((60*SLOW))); do $ADB logcat -d -s Glance:I | grep -q "Loop running" && break; sleep 0.5; done
sleep $((2*SLOW))   # let the 2 fps stream fill the buffer
# One quoted string: `adb shell` re-joins argv through sh, so multi-word extras must be quoted *inside* (bug found 2026-10-10).
$ADB shell "am broadcast -a dev.arash.glance.DEBUG_COMMAND -n $PKG/glance.app.debug.DebugCommandReceiver --es text '$TEXT' --ez viaMockSpeech $VIA" >/dev/null
for i in $(seq 1 $((60*SLOW))); do
  OUT=$($ADB logcat -d -s GlanceHud:I | sed -n 's/.*GlanceHud: //p')
  echo "$OUT" | grep -qE "state=(Answer|Logged|Error)" && break; sleep 0.5
done
echo "$OUT"
echo "$OUT" | grep -qE "state=(Answer|Logged)" && { echo "SMOKE PASS"; exit 0; } || { echo "SMOKE FAIL"; exit 1; }
