#!/usr/bin/env bash
# Usage: connect.sh pair <tsIP> <pairPort> <code> <tlsPort> | connect.sh reconnect <tlsPort> | connect.sh ensure
set -uo pipefail
ADB=${ADB:-$HOME/android-sdk/platform-tools/adb}
CFG=$HOME/.config/glance; mkdir -p "$CFG"; chmod 700 "$CFG"
ENV=$CFG/phone.env; [ -f "$ENV" ] && . "$ENV"
case "${1:-ensure}" in
  pair)
    IP=$2; "$ADB" pair "$IP:$3" "$4" || exit 1
    "$ADB" connect "$IP:$5" || exit 1
    "$ADB" -s "$IP:$5" tcpip 5555 && sleep 3
    "$ADB" connect "$IP:5555" || exit 1
    printf 'PHONE_IP=%s\nPHONE=%s:5555\n' "$IP" "$IP" > "$ENV"; chmod 600 "$ENV" ;;
  reconnect)
    "$ADB" connect "$PHONE_IP:$2" && "$ADB" -s "$PHONE_IP:$2" tcpip 5555 && sleep 3 && "$ADB" connect "$PHONE" ;;
  ensure)
    : "${PHONE:?not paired yet — run pair first}"
    st=$("$ADB" -s "$PHONE" get-state 2>&1)
    if [ "$st" != "device" ]; then "$ADB" connect "$PHONE" >/dev/null 2>&1; sleep 2; st=$("$ADB" -s "$PHONE" get-state 2>&1); fi
    echo "$PHONE: $st"
    [ "$st" = "device" ] || exit 2 ;;
esac
