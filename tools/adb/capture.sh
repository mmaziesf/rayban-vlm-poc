#!/usr/bin/env bash
# Screenshot (only if Glance is foreground) + perf dumps.
set -uo pipefail
ADB=${ADB:-$HOME/android-sdk/platform-tools/adb}; . "$HOME/.config/glance/phone.env"
OUT=$(cd "$(dirname "$0")/../.." && pwd)/artifacts/capture/$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
if "$ADB" -s "$PHONE" shell dumpsys activity activities | grep -q 'topResumedActivity.*dev.arash.glance'; then
  "$ADB" -s "$PHONE" exec-out screencap -p > "$OUT/screen.png"
else echo "Glance not in foreground — skipping screenshot (privacy rule)"; fi
"$ADB" -s "$PHONE" shell dumpsys meminfo dev.arash.glance > "$OUT/meminfo.txt"
"$ADB" -s "$PHONE" shell dumpsys gfxinfo dev.arash.glance > "$OUT/gfxinfo.txt"
"$ADB" -s "$PHONE" shell dumpsys batterystats dev.arash.glance > "$OUT/batterystats.txt"
echo "$OUT"
