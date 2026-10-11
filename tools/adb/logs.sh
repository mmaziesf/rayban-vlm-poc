#!/usr/bin/env bash
# Capture N seconds of logcat limited to the Glance process + crash buffer. Never captures other apps' logs.
set -uo pipefail
ADB=${ADB:-$HOME/android-sdk/platform-tools/adb}; . "$HOME/.config/glance/phone.env"
SECS=${1:-30}; OUT=$(cd "$(dirname "$0")/../.." && pwd)/artifacts/logs; mkdir -p "$OUT"; TS=$(date +%Y%m%d-%H%M%S)
PID=$("$ADB" -s "$PHONE" shell pidof -s dev.arash.glance | tr -d '\r')
[ -n "$PID" ] || { echo "Glance not running"; exit 1; }
timeout "$SECS" "$ADB" -s "$PHONE" logcat -v threadtime --pid="$PID" > "$OUT/$TS.txt"
"$ADB" -s "$PHONE" logcat -b crash -d | grep -A40 'dev.arash.glance' > "$OUT/$TS.crash.txt" || true
echo "$OUT/$TS.txt"
