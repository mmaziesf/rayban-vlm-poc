#!/usr/bin/env bash
# Build (if Android SDK present), install, launch Glance on the paired phone.
set -euo pipefail
ADB=${ADB:-$HOME/android-sdk/platform-tools/adb}; . "$HOME/.config/glance/phone.env"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APK=$ROOT/phone/app/build/outputs/apk/debug/app-debug.apk
if [ -n "${ANDROID_HOME:-}" ] && [ -x "$ROOT/phone/gradlew" ]; then (cd "$ROOT/phone" && ./gradlew -q assembleDebug); fi
[ -f "$APK" ] || { echo "no APK at $APK"; exit 1; }
"$ADB" -s "$PHONE" install -r -t "$APK"
"$ADB" -s "$PHONE" shell am start -n dev.arash.glance/glance.app.MainActivity
