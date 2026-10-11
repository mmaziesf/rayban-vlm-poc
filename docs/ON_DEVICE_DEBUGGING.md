# On-device development & bot-driven debugging (Android, autonomy-first)

Researched 2026-10-10 (PT). **High** = official doc read; **Med** = reputable 3rd-party / GitHub issue; **Est** = inference. Goal: **Grok Bot drives build → install → test → logcat → fix on Arash's Android phone with no human in the loop**, except a short one-time setup.

---

## 0. Topology (be precise)

```
 ┌──────────── Grok Bot box (Linux, cloud) ─────────────┐        ┌──── Arash's home / pocket ────┐
 │ JDK 17, kotlinc, Android SDK 35, Gradle, adb, Chrome │        │ Android phone (Meta AI app,   │
 │ /dev/net/tun + sudo present → kernel Tailscale OK    │        │ Glance debug APK, Tailscale)  │
 │ /dev/kvm present (needs group grant) → emulator OK?  │        │        ▲ BT / Wi-Fi           │
 │ outbound-only NAT (172.30.0.2), no inbound ports     │        │        ▼                      │
 └──────────────────────────────────────────────────────┘        │ Ray-Ban Display glasses       │
                       ▲      WireGuard tailnet (NAT traversal / DERP relay)       └───────────────┘
                       └───────────────────────────────────────────────────────────────▲
```

- The box is **not** on Arash's LAN and cannot accept inbound connections. Anything that says "same Wi-Fi network" (Android Studio pairing, mDNS discovery, `adb connect 192.168.x.x`) **does not work from the box** without a tunnel.
- Recommended tunnel: **Tailscale on both the phone and the box.** The box has `/dev/net/tun` and sudo, so normal kernel mode works. Userspace mode would need a SOCKS proxy, which `adb` doesn't natively use.
  - [Tailscale userspace networking](https://tailscale.com/docs/concepts/userspace-networking) (High)
  - [Tailscale issue #1990](https://github.com/tailscale/tailscale/issues/1990) (Med): adb over Tailscale works with explicit IP pairing.
  - [Agent + ADB + Tailscale guide](https://gist.github.com/subliterate/6e01dc609b8f100d089c973edabb2479) (Med)

## 1. Bot-owned loops vs one-time human steps

### Tier 0: box only (zero human, daily default)
| Loop | Status |
|---|---|
| Core logic JVM tests (`phone/core/run-tests.sh`) | ✅ working (40/40) |
| Web HUD QA headless at 600×600 (`tools/qa.mjs`) | ✅ working (20/20) |
| Android build (`./gradlew assembleDebug`) | ✅ D0 done: `source tools/env.sh && cd phone && ./gradlew :app:assembleDebug` (SDK 468 MB + Gradle cache 1.1 GB) |
| Android emulator + **Mock Device Kit** (RBD display, H.265 mock camera feed, `MockSpeechKit.simulateTranscription`, `simulateLaunchAppAction`) + Chrome **Display Simulator extension on the box's own browser** at `127.0.0.1:9000` | Feasible (Est). `/dev/kvm` exists but the box user needs group access (`sudo usermod -aG <kvm gid> box`). RAM is tight: 15 GB total, ~11 GB already used by other agents. VLM on emulator: use `CannedVlmEngine`, or llama.cpp on the box CPU for prompt evaluation. |

### Tier 1: physical phone over the tailnet (bot-driven, no glasses)
The phone runs the **real** model on its real GPU with **Mock Device Kit** as the glasses: mock display, mock camera from a bundled H.265 clip, mock speech.

This covers M1b, M1c and M2 end to end, including real Gemma 4 E4B latency and memory, **without anyone wearing glasses or tapping buttons**:
- **Mock Device Kit works with a physical Android device.** Display preview via `adb forward tcp:9000 tcp:9000` "works with an Android emulator or an Android device connected through ADB" ([display-simulation](https://wearables.developer.meta.com/docs/develop/dat/display-simulation), High). Over the tailnet, the bot runs that `adb forward` from the box and opens the preview in the box's Chrome with the simulator extension.
- **Instrumentation tests.** MDK is designed for them ([testing-mdk-android](https://wearables.developer.meta.com/docs/develop/dat/testing-mdk-android/), High). The bot runs `adb shell am instrument …` and parses results.
- **What the bot can do over adb (High):**
  - install, launch, clear app data, logcat streaming and filters, screencap, screenrecord, bugreport
  - `dumpsys meminfo`, `dumpsys batterystats`, `dumpsys gfxinfo`
  - push the model file, `input` events, `uiautomator dump`
  - Source: [adb docs](https://developer.android.com/tools/adb)
- **scrcpy** mirrors and records over the same adb connection ([connection](https://github.com/Genymobile/scrcpy/blob/master/doc/connection.md), [tunnels](https://github.com/Genymobile/scrcpy/blob/HEAD/doc/tunnels.md), High). On the box it can run in the bot's desktop window or headless, recording to a file. Exact headless flag names vary by version: check `scrcpy --help` (Est).

### Tier 2: real glasses (bot-driven after a one-time setup; physical conditions needed)
- After registration and permissions are granted once, the bot can launch the app (`adb shell am start`), start the DAT session, stream, collect logs and run the measurement plan (`STREAMING_BUFFER.md` §4).
- The glasses must be **charged, powered on, connected to the phone, and hinge open**: `HINGE_CLOSED` stops streaming, and `DeviceState` reports don/hinge ([device-state](https://wearables.developer.meta.com/docs/develop/dat/device-state/), High).
- **Unknown:** whether camera, display or speech sessions run while the glasses are **not worn** (DOFFED). If DOFFED blocks them, M3 needs a human wearing the glasses, or a "glasses on a stand" test if don detection allows it.
- Voice input on real glasses needs someone speaking. Bot-side substitute: `MockSpeechKit` with the real camera isn't possible (mock and real devices are separate). So for real-hardware runs, trigger commands from a debug intent instead: `adb shell am broadcast -a glance.DEBUG_COMMAND --es text "what am I seeing"`. TODO in app.

## 2. Steps that STILL need a human (one-time unless noted)

| # | Step | Why it can't be automated | Frequency |
|---|---|---|---|
| H1 | Phone: enable **Developer options**, **USB debugging**, **Wireless debugging**; turn on **"Disable adb authorization timeout"** (otherwise keys are revoked after 7 days of disuse). Optional: Stay awake while charging. | On-device settings UI; security gate | Once |
| H2 | Install **Tailscale** on the phone, sign in, disable battery optimization for it, keep the VPN on | Account login | Once |
| H3 | Join the **box to the same tailnet**: Arash creates a **tagged, pre-approved auth key** (preferably ephemeral = false, reusable = false) and gives it to the bot, **or** opens the login URL the bot prints. Add an **ACL** so only the box can reach the phone on adb ports. | Account login / admin console | Once |
| H4 | First adb authorization: on the phone, Wireless debugging → **Pair device with pairing code**. Send the bot the 6-digit code + pairing `IP:port` (Tailscale IP + pairing port) + the main "IP address & Port". The bot runs `adb pair` / `adb connect`. | Pairing secret is shown only on the phone screen | Once per box key |
| H5 | **Meta AI app:** pair the glasses; Settings → App Info → tap App version 5× → **Developer Mode** on ([getting started](https://wearables.developer.meta.com/docs/develop/dat/getting-started-toolkit), High). Glasses/app versions must meet [version dependencies](https://wearables.developer.meta.com/docs/develop/dat/version-dependencies). | Account + device consent | Once |
| H6 | Approve the Glance app **registration** in Meta AI and the DAT **camera permission** when the bot launches the flow. Registration needs internet ([permissions skill](https://raw.githubusercontent.com/facebook/meta-wearables-dat-android/main/plugins/mwdat-android/skills/permissions-registration/SKILL.md), High). | User consent screens; the bot should not click through consent on the user's behalf | Once (again if the app data is cleared) |
| H7 | Accept the **Gemma license** on Hugging Face if the `.litertlm` download is gated (VERIFY). The bot then downloads to the box and `adb push`es it to the phone. | Account terms acceptance | Once |
| H8 | **After a phone reboot:** legacy `adb tcpip 5555` mode is lost. Wireless debugging may need re-enabling (it can auto-re-enable on a trusted network, Med). If the phone shows a new random TLS port, the bot needs it (one message) unless it can rediscover it. | No supported way for non-root apps to enable adbd | Per reboot (rare) |
| H9 | Real-hardware sessions only: glasses charged, on, hinge open (worn if DOFFED blocks capture); someone speaks if testing real ASR | Physical | Per M3 test session |

Everything else (builds, installs, test runs, log capture, crash triage, perf measurement, iteration) is **bot-owned**.

## 3. Connection procedure (summary; exact commands in `BOT_ADB_RUNBOOK.md`)

1. H1–H4.
2. The bot pairs and connects over the tailnet:
   - `adb pair 100.x.y.z:<pairPort> <code>`
   - `adb connect 100.x.y.z:<tlsPort>`
   - (Pairing with an explicit IP works over Tailscale per issue #1990. mDNS discovery does not cross the tailnet.)
3. The bot switches to a **fixed port** while connected: `adb -s 100.x.y.z:<tlsPort> tcpip 5555`, then `adb connect 100.x.y.z:5555`.
   - Fixed port = scripts don't need the random TLS port again until the next reboot.
   - Caveat: legacy tcpip mode isn't TLS-encrypted by adb. It's acceptable **only** because the tailnet (WireGuard) encrypts it and the ACL limits reachability ([ADB Wi-Fi architecture](https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md), High).
   - Alternative: stay on the TLS wireless port and accept that the human must resend the port after reboots.
4. Health check every loop: `adb -s $PHONE get-state`; on failure, `adb connect` again; on `unauthorized`, escalate to a human (H4).

## 4. Other bridges considered

| Option | Works from cloud box? | Verdict |
|---|---|---|
| **Tailscale (phone + box)** | Yes (NAT traversal or DERP relay) | **Recommended.** No user PC needed. Phone can be on any network, even cellular. |
| ZeroTier / other mesh VPN | Yes, same idea | Equivalent alternative. Not researched in depth. |
| User's PC as jump host: PC on LAN runs adb (USB or LAN), PC joins tailnet as a **subnet router**, or exposes its adb server (`adb -a` / `ADB_SERVER_SOCKET`) via SSH tunnel ([scrcpy tunnels](https://github.com/Genymobile/scrcpy/blob/HEAD/doc/tunnels.md)) | Yes, if the PC stays on | Fallback if Tailscale can't run on the phone. The adb server protocol is **unencrypted**, so it must ride inside SSH or the tailnet. The PC must stay awake. |
| USB-over-IP (usbip from PC) | Technically | Not recommended: fragile, Windows drivers, still needs the PC. |
| Firebase Crashlytics / remote logging | Yes (no adb) | Only for crash reports, not control. Needs internet + Google services, which conflicts with the offline product design. OK only in debug builds. Not a substitute for adb. |
| Exposing adb port 5555 to the internet / port-forward on router | — | **Never.** Anyone reaching the port gets a full shell ([gist](https://gist.github.com/subliterate/6e01dc609b8f100d089c973edabb2479), Med; [adb_wifi](https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md)). |
| **Fallback, no remote access:** user runs `adb logcat -d > log.txt` / `adb bugreport` and emails it or pastes it | Yes | Last resort. Breaks autonomy. The bot has its own inbox and can read attachments. |

## 5. Security & privacy caveats

- **ADB = near-full control of the phone.** It can install/uninstall apps, read the shell-accessible filesystem and debuggable apps' data, capture the screen, inject input, and read logs from all apps. Granting it to the bot is a real trust decision.
  - Mitigations: tailnet ACL (only the box → phone:5555 and the wireless TLS port), Tailscale key expiry, revoke anytime via *Developer options → Revoke USB debugging authorizations* or by turning off Wireless debugging.
- **Bot conduct rules** (proposed, for the user to confirm):
  - Only touch package `dev.arash.glance` and the Meta AI app's visible state.
  - logcat filtered to our tags and package PID: `adb logcat --pid=$(adb shell pidof dev.arash.glance)` plus `Glance:*`, `LiteRtLm:*`, and DAT tags.
  - Screenshots/recordings only while Glance is in the foreground. No browsing personal apps, messages or photos.
  - No `uiautomator` clicks on consent or permission screens.
- **adb key on the box:** `~/.android/adbkey` lives on a **shared box** that all of Arash's agents can access. Treat it as a credential: `chmod 600`, never print or log it, rotate by revoking on the phone.
- **Glasses camera privacy:**
  - Stream frames include bystanders. Keep the ring buffer in RAM only.
  - Never log image bytes. Never `screenrecord` while the real camera feed is shown unless the user asked.
  - Prefer the **bundled H.265 mock clip** for all automated runs.
  - Real-hardware recordings stay on the phone unless the user approves pulling them.
- **Legacy `adb tcpip` mode** has no adb-level TLS. Use it only inside the tailnet.
- **Meta AI Developer Mode** lets unpublished apps register with the glasses. Disable it when not developing.

## 6. Emulator vs physical phone

| | Emulator (box) | Physical phone (tailnet) |
|---|---|---|
| Mock Device Kit RBD + display preview | Yes (documented) | Yes (documented) |
| Meta AI app / real glasses | No (no Bluetooth to real glasses) | Yes |
| Gemma 4 E4B | Impractical: no mobile GPU delegate; ~3.6 GB model + x86 CPU (Est) | Real GPU numbers (target) |
| Speed of loop | Fast, no network dependency | Depends on tailnet path. Pushing the 3.65 GB model over a DERP relay may be slow (one-time) |
| Human needed | None | One-time H1–H4, H7 |

## 7. Useful adb commands (all from the box)

```bash
P=100.x.y.z:5555
adb -s $P install -r -t app/build/outputs/apk/debug/app-debug.apk
adb -s $P shell am start -n dev.arash.glance/glance.app.MainActivity
adb -s $P shell am force-stop dev.arash.glance
adb -s $P logcat -c && adb -s $P logcat -v threadtime --pid=$(adb -s $P shell pidof -s dev.arash.glance)
adb -s $P logcat -b crash -d                    # recent crashes
adb -s $P exec-out screencap -p > shot.png
adb -s $P shell screenrecord --time-limit 30 /sdcard/glance.mp4 && adb -s $P pull /sdcard/glance.mp4
adb -s $P bugreport ./bugreport.zip
adb -s $P shell dumpsys meminfo dev.arash.glance
adb -s $P shell dumpsys batterystats --charged dev.arash.glance
adb -s $P push gemma-4-E4B-it.litertlm /data/local/tmp/
adb -s $P forward tcp:9000 tcp:9000             # MDK display preview → box Chrome + simulator extension
adb -s $P shell am instrument -w -r dev.arash.glance.test/androidx.test.runner.AndroidJUnitRunner
```
