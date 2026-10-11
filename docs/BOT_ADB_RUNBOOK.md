# Bot ADB runbook (box → Arash's Android phone over Tailscale)

Run by Grok Bot from the box. Human steps are marked 👤. Scripts live in `tools/adb/`.
Do not run anything here until Arash has completed 👤 H1–H4 from `ON_DEVICE_DEBUGGING.md` §2.

## A. One-time: join the box to the tailnet
```bash
curl -fsSL https://tailscale.com/install.sh | sh          # installs tailscale + tailscaled (Debian 13 box)
sudo systemctl enable --now tailscaled || sudo tailscaled --state=/var/lib/tailscale/tailscaled.state &
sudo tailscale up --auth-key="$TS_AUTHKEY" --hostname=grokbot-box   # 👤 key from Arash (tagged, pre-approved)
# or: sudo tailscale up → prints a login URL → 👤 Arash opens it once
tailscale status            # confirm the phone (e.g. "pixel") is listed; note its 100.x.y.z
```
👤 Recommended ACL in the Tailscale admin console:
- Allow only `tag:grokbot` → `<phone>` on TCP 5555 and the wireless-debugging port range.
- Deny everything else to the phone.

## B. One-time: pair adb (👤 sends 3 values)
👤 Phone: Developer options → Wireless debugging → *Pair device with pairing code*. Send the bot:
- the pairing **port** and **6-digit code**
- the **"IP address & Port"** shown on the main Wireless debugging screen (only the port matters; the bot uses the Tailscale IP)

```bash
tools/adb/connect.sh pair 100.x.y.z <pairPort> <code> <tlsPort>
# = adb pair 100.x.y.z:<pairPort> <code>; adb connect 100.x.y.z:<tlsPort>; adb tcpip 5555; adb connect 100.x.y.z:5555
```
`tools/adb/connect.sh` writes `PHONE=100.x.y.z:5555` to `~/.config/glance/phone.env` (not in the repo).

## C. Every loop (bot-owned)
```bash
tools/adb/connect.sh ensure                # reconnects; exits 2 if unauthorized/unreachable → notify Arash
tools/adb/deploy.sh                        # build (when SDK present), install -r, launch
tools/adb/logs.sh 60                       # 60 s filtered logcat → artifacts/logs/<ts>.txt (+ crash buffer)
tools/adb/capture.sh                       # screenshot + meminfo + gfxinfo + batterystats → artifacts/
```

## D. After a phone reboot
1. `connect.sh ensure` fails (port 5555 is gone).
2. If Wireless debugging re-enabled itself: 👤 send the new "IP address & Port". Then run `connect.sh reconnect <tlsPort>`, which also re-runs `tcpip 5555`.
3. Otherwise: 👤 toggle Wireless debugging on, then step 2.

## E. Escalation rules
- `unauthorized` → stop; ask Arash to accept the prompt or re-pair. Never try to bypass it.
- A consent or permission screen appears (Meta AI registration, DAT camera, Android runtime permission) → screenshot it, ask Arash to approve. The bot doesn't tap consent.
- Anything outside `dev.arash.glance` → don't touch it.

## F. Revoke access (👤, any time)
- Phone: Developer options → **Revoke USB debugging authorizations**, or turn Wireless debugging off.
- Tailscale admin: remove the `grokbot-box` node.
