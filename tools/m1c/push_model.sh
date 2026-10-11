#!/usr/bin/env bash
# Push the staged model to the connected device (ANDROID_SERIAL honored). Needs the app installed once
# (so Android/data/dev.arash.glance exists). ~3.66 GB over USB/Wi-Fi adb: minutes.
set -euo pipefail
source "$(dirname "$0")/../env.sh" 2>/dev/null || true
PKG=dev.arash.glance; NAME=gemma-4-E4B-it.litertlm; SRC=${MODEL:-$HOME/models/$NAME}; SIZE=3659530240
DST=/sdcard/Android/data/$PKG/files/models
[[ -f "$SRC" ]] || { echo "missing $SRC: run tools/m1c/fetch_model.sh" >&2; exit 2; }
adb shell mkdir -p "$DST"
got=$(adb shell stat -c %s "$DST/$NAME" 2>/dev/null | tr -d '\r' || true)
if [[ "$got" == "$SIZE" ]]; then echo "already on device ($got bytes)"; else adb push "$SRC" "$DST/$NAME"; fi
got=$(adb shell stat -c %s "$DST/$NAME" | tr -d '\r'); [[ "$got" == "$SIZE" ]] || { echo "size mismatch on device: $got" >&2; exit 3; }
echo "PUSH_OK $DST/$NAME"
# Fallback if the app can't read external app dir on some OEM build (debug APK only):
#   adb shell "run-as $PKG sh -c 'mkdir -p files/models && cat $DST/$NAME > files/models/$NAME'"
