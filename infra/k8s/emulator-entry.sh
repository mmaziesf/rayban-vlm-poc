#!/usr/bin/env bash
# Boots the AVD headless and exposes adb on :5555 for other pods. ACCEL=on needs /dev/kvm (KVM node); ACCEL=off = TCG (any node, ~10x slower).
set -e
ACCEL=${ACCEL:-off}
[ "$ACCEL" = on ] && [ ! -w /dev/kvm ] && { echo "ACCEL=on but /dev/kvm not usable"; exit 1; }
emulator -avd glance -accel "$ACCEL" -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader -memory 1536 -cores "${CORES:-4}" -no-metrics &
# emulator's adb port listens on 127.0.0.1 only → publish it on the pod IP
socat TCP-LISTEN:5556,fork,reuseaddr TCP:127.0.0.1:5555 &
adb wait-for-device; until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 5; done
echo BOOTED; touch /tmp/booted; wait
