#!/usr/bin/env bash
# Software-only (TCG) Android emulator for the bot box. NO KVM: nested KVM on this host oopses the kernel
# (see docs/EMULATOR_ALTERNATIVES.md). Safe by construction: -accel off, and the box user is not in /dev/kvm's group.
#   tools/emu/tcg.sh up      # create AVD if needed, boot headless (≈3 min), watchdog: abort if MemAvailable < 1500 MB or > 420 s
#   tools/emu/tcg.sh down    # adb emu kill (+ kill -9 fallback)
#   tools/emu/tcg.sh status
# Then: SMOKE_SLOW=6 ANDROID_SERIAL=emulator-5554 tools/adb/smoke.sh
#       adb shell am instrument -w -e timeoutScale 6 -e class glance.app.MockLoopTest dev.arash.glance.test/androidx.test.runner.AndroidJUnitRunner
set -euo pipefail
source "$(dirname "$0")/../env.sh" >/dev/null
IMG="system-images;android-29;default;x86_64"; AVD=tcg29; ADB="$ANDROID_HOME/platform-tools/adb -s emulator-5554"
LOG=/workspace/artifacts/tcg_emulator.log; mkdir -p /workspace/artifacts
case "${1:-status}" in
up)
  if [ -w /dev/kvm ]; then echo "REFUSING: /dev/kvm is writable by $(id -un); nested KVM crashes this host kernel. Remove access first."; exit 1; fi
  [ -d "$ANDROID_HOME/emulator" ] && [ -d "$ANDROID_HOME/system-images/android-29/default/x86_64" ] || yes | sdkmanager "emulator" "$IMG" >/dev/null
  if [ ! -d ~/.android/avd/$AVD.avd ]; then
    echo no | avdmanager create avd -n $AVD -k "$IMG" -d pixel --force >/dev/null
    sed -i 's/^hw.ramSize=.*/hw.ramSize=1536/; s/^hw.lcd.height=.*/hw.lcd.height=800/; s/^hw.lcd.width=.*/hw.lcd.width=480/; s/^hw.lcd.density=.*/hw.lcd.density=240/' ~/.android/avd/$AVD.avd/config.ini
  fi
  nohup "$ANDROID_HOME/emulator/emulator" -avd $AVD -accel off -no-window -no-audio -no-boot-anim -no-snapshot \
    -gpu swiftshader -memory 1536 -cores 4 -no-metrics > "$LOG" 2>&1 &
  EP=$!; S=$(date +%s)
  while :; do
    T=$(( $(date +%s) - S )); M=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    kill -0 $EP 2>/dev/null || { echo "emulator exited after ${T}s"; tail -5 "$LOG"; exit 2; }
    [ "$M" -lt 1500 ] && { echo "low memory (${M} MB): killing"; kill -9 $EP; exit 3; }
    [ "$(timeout 5 $ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && { echo "booted in ${T}s (pid $EP)"; exit 0; }
    [ $T -ge 420 ] && { echo "boot cap reached: killing"; kill -9 $EP; exit 4; }
    sleep 15
  done ;;
down)
  timeout 20 $ADB emu kill 2>/dev/null || true; sleep 5
  P=$(pgrep -f "qemu-system-x86_64.*-avd $AVD" || true); [ -n "$P" ] && kill -9 $P || true; echo down ;;
status) timeout 5 $ADB get-state 2>/dev/null || echo "not running" ;;
esac
