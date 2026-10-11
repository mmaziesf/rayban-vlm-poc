# Milestone plan (autonomy-first)

**Principle:** Grok Bot owns the build → deploy → test → debug loop.
- Humans do **one-time setup** only (H1–H9 in `ON_DEVICE_DEBUGGING.md` §2).
- Daily iteration uses Mock Device Kit, a bundled H.265 clip and mock speech, so **nobody wears glasses** until M3.

**Other decisions:**
- **Platform:** Android first.
- **Frames:** 2 fps stream + rolling buffer preferred; Photo/`capturePhoto` as fallback (`STREAMING_BUFFER.md`).

**Tiers** (from `ON_DEVICE_DEBUGGING.md` §1):
- **T0** = box only
- **T1** = physical phone over the tailnet, with mock glasses
- **T2** = real glasses

| # | Slice | Tier | Bot-owned exit check | Human (one-time) | Status |
|---|---|---|---|---|---|
| M1a | Web HUD prototype | T0 | `tools/qa.mjs` 20/20; simulator extension QA in the box's Chrome | none | Local QA ✅; extension run TODO (install extension in box Chrome) |
| **D0** | **Bot dev rig: box side.**<br>• Android cmdline-tools + SDK + Gradle on box<br>• `assembleDebug` green<br>• **on-box emulator** | T0 | `./gradlew assembleDebug` passes; emulator runs the suite | none | ✅ **Done 2026-10-10.**<br>• Build: `:core` + `:app` debug/release/androidTest green; core tests 41/41.<br>• **KVM emulator ❌**: nested KVM oopsed the box kernel (`arch/x86/kvm/x86.c:702`). Reverted; **never re-enable**.<br>• **TCG (software) emulator ✅**: `tools/emu/tcg.sh up` boots API 29 x86_64 headless in 191 s with `-accel off` (box can't open `/dev/kvm`, so kernel-safe). 1.5 GB guest, peak about 2.5 GB host RAM. `tcg.sh down` afterwards.<br>• Details: `docs/EMULATOR_ALTERNATIVES.md`. |
| **D1** (now *backup* + required for M1c GPU/M3) | **Bot ↔ phone link.** Tailscale on box + phone; adb pair → `tcpip 5555`; `tools/adb/connect.sh ensure` returns `device` | T1 | `connect.sh ensure` exit 0; `deploy.sh` installs and launches | **H1–H4** (≈10 min total) | Runbook + scripts ready; waiting on Arash. No longer blocks M1b/M2/M2.5 (TCG emulator). Still needed for real GPU inference timings (M1c) and real glasses (M3) |
| M1b | DAT shell + MDK RBD Display HUD | T0 (TCG emu) / T1 | `MockLoopTest.displayIdleShowsLiveBuffer` + HUD lines in logcat | none. **Verified:** MDK needs no Meta AI registration (`MockDeviceKitConfig(true,true)`) | ✅ **PASS on TCG emulator 2026-10-10.** Mock RBD pairs → CONNECTED → session (Display + Camera + Speech) → HUD renders. Chrome preview server needs INTERNET, which was added to debug only. It still fails to bind on the emulator, so the preview is not yet seen (non-fatal) |
| M1c | Real Gemma 4 E4B inference on the phone GPU from a bundled frame | T1 (phone D1 or a cloud *physical* GPU device; **not** the TCG emulator) | `tools/m1c/run_real.sh` → `GlanceVlm: load_ms / infer_ms` → `parse_timings.sh` (PASS if p50 < 5 s). Offline proof: release APK has no INTERNET (`aapt dump permissions`, re-checked 2026-10-10) | ~~H7~~ **resolved**: Apache-2.0, HF repo not gated. Needs **D1** (a device) | 🟡 **Prep done 2026-10-10, nothing run on a GPU yet.**<br>• `VlmFactory` + `VlmSelection`: stub/real with logged fallback reasons; 8 new JVM tests, core **49/49**<br>• `-Pglance.vlm=real` build flag; debug override `--es vlm real`<br>• Model on the box, sha256 OK (`~/models`)<br>• Scripts: `tools/m1c/{fetch_model,push_model,run_real,parse_timings}.sh`<br>• Doc: `docs/M1C_REAL_VLM.md` |
| M2 | Voice + buffer with mocks: `MockSpeechKit.simulateTranscription` → IntentRouter → buffer frame from the H.265 mock feed → VLM (canned) → HUD + TTS | T0 (TCG emu) / T1 | `MockLoopTest` asserts HUD sequence + `source=pinned/buffer`; core JVM 41/41 | none | ✅ **PASS on TCG emulator: `MockLoopTest` OK (4 tests)** (`am instrument -e timeoutScale 6`). Mock H.265 feed decodes (`OMX.google.hevc.decoder`) → 504×896 `STREAM_BUFFER` frames; describe → `buffer`/`pinned`, log → `Logged`. `simulateLaunchAppAction` not yet asserted |
| M2.5 | Debug command intent (`am broadcast … DEBUG_COMMAND`) so the bot can trigger turns without anyone speaking | T0/T1 | Broadcast → full turn in logcat | none | ✅ **PASS on TCG emulator.** `SMOKE_SLOW=6 tools/adb/smoke.sh` → SMOKE PASS for both broadcast and `--via-mock-speech` paths. Same commands will work on the phone (D1) |
| M3 | **Real glasses**:<br>• registration + permission<br>• 2 fps stream<br>• measurements (`STREAMING_BUFFER.md` §4) driven by the bot via debug intents; results parsed from logcat | T2 | Measurement report auto-generated from logs | **H5, H6** once; **H9** per session (glasses on, hinge open; worn if DOFFED blocks capture) | |
| M4 | "Log this meal": JSON → Room; buffer frame + optional `capturePhoto` | T1 (mock) → T2 | Instrumented DB test + logcat | none | |
| M5 | Multi-turn chat over pinned frame | T1 | 3-turn instrumented test, no crash | none | |
| M6 | Hardening:<br>• sentence-streamed TTS<br>• idle-timeout / arm-on-partial<br>• thermal back-off<br>• E2B fallback | T1/T2 | 60-min soak run by the bot, with `dumpsys` + logcat summaries | H9 for the real-glasses soak | |
| M7 | iOS port (optional): `ios/GlanceCore` (pure Swift core) + `ios/GlanceApp` (SwiftUI + DAT iOS + MockDeviceKit) | T0 (Linux: core only) / Mac CI (GitHub Actions macOS) / T2 (iPhone) | Linux: `ios/GlanceCore/run-tests.sh`. CI: `.github/workflows/ios.yml` on https://github.com/mmaziesf/rayban-vlm-poc | none (repo exists) | 🟢 **DAT mock link works on CI (2026-10-11 02:15 PT, run [38126000773](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38126000773)):**<br>• **Gate (Xcode 16.4, macos-15):** GlanceCore 11/11 (Linux + macOS) + Simulator build (+ built-Info.plist `MWDAT` check) + **`MockLoopUITests` 4/4 ✅** (real DAT MockDeviceKit session: Camera, Speech, Display) + `FakeGlassesUITests` 4/4 ✅ (backup gate)<br>• **Xcode 26.6 / macos-26 leg:** same, 4/4 + 4/4; **gating as well** since a session-start race was fixed (`waitForStarted` now also polls `state`)<br>• **Root cause of the old 0/4:** XcodeGen `info: { path: Info.plist }` rewrote Info.plist with only default keys. The built app had no `MWDAT` dict, URL scheme or Bonjour/LocalNetwork keys, so the mock device stayed `disconnected/undefined`. Fix: `INFOPLIST_FILE` setting. Display/Speech linkage, bundle id, pairing order, entitlements and Xcode version were all ruled out<br>• Open: real iPhone + glasses (T2) unverified; on-device VLM on iOS still a stub. Details: `docs/IOS_OPTIONS.md` |

## Daily loop (bot, no human)
1. Edit code.
2. `phone/core/run-tests.sh`.
3. Device tests. Either option:
   - On-box (no human): `tools/emu/tcg.sh up` → `adb install` both APKs → `am instrument -e timeoutScale 6 …` + `SMOKE_SLOW=6 tools/adb/smoke.sh` → `tcg.sh down`. About 10 min end to end.
   - On the phone (D1): `./gradlew connectedDebugAndroidTest`.
   - Later, a k8s cluster with KVM nodes: `infra/k8s/up.sh kvm` (`docs/K8S_ANDROID_ENV.md`).
4. `logs.sh` / `capture.sh`.
5. Triage → fix → repeat.
6. Report results; ask a human only on escalation (`BOT_ADB_RUNBOOK.md` §E).
