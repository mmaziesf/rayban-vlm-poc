#!/usr/bin/env bash
# M1c on a REAL GPU device (phone D1 or a cloud physical device with adb). Not for the TCG emulator (no GPU delegate,
# 1.5 GB RAM) — VlmFactory would fall back to stub and say why.
# Steps: build real-VLM debug APK → install → push model → launch with --es vlm real → trigger N turns → timings.
set -euo pipefail
cd "$(dirname "$0")/../.."; source tools/env.sh 2>/dev/null || true
N=${N:-5}; PKG=dev.arash.glance
( cd phone && ./gradlew -q :app:assembleDebug -Pglance.vlm=real )
adb install -r -g phone/app/build/outputs/apk/debug/app-debug.apk
tools/m1c/push_model.sh
adb logcat -c
adb shell am force-stop $PKG
adb shell am start -n $PKG/glance.app.MainActivity --es vlm real
# wait for model load (or a stub fallback line)
for i in $(seq 1 90); do adb logcat -d -s GlanceVlm | grep -qE "load_ms=|mode=STUB" && break; sleep 2; done
adb logcat -d -s GlanceVlm | grep -E "mode=|load_ms=" || true
adb logcat -d -s GlanceVlm | grep -q "mode=REAL" || { echo "REAL engine not selected (see reason above)" >&2; exit 4; }
for i in $(seq 1 "$N"); do
  adb shell "am broadcast -a dev.arash.glance.DEBUG_COMMAND -n $PKG/glance.app.debug.DebugCommandReceiver --es text 'what am I seeing'" >/dev/null
  sleep 20
done
adb logcat -d -s GlanceVlm GlanceHud > /tmp/m1c_logcat.txt
tools/m1c/parse_timings.sh /tmp/m1c_logcat.txt
