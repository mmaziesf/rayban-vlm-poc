# phone/ — Android companion app (M1b/M2 scaffold)

> **Start with the [root README](../README.md)** for build, test, emulator and real-hardware instructions (Android + iOS). This file has Android implementation details.

Android first (see `docs/MILESTONE1_RESEARCH.md` §6).

```
phone/
├── settings.gradle.kts, build.gradle.kts, gradle/libs.versions.toml
├── core/                      Pure Kotlin/JVM: no Android, DAT or LiteRT-LM deps → unit-testable anywhere
│   ├── src/main/kotlin/glance/core/
│   │   ├── Intents.kt         IntentRouter: transcript → Describe | LogMeal | Chat | Unknown; isVisionHint(partial)
│   │   ├── Frames.kt          Frame, Sharpness (luma Laplacian), FrameRingBuffer (select/pin)
│   │   ├── FrameSources.kt    BufferedFrameSource: pinned → buffer (≤1.5 s) → on-demand capture fallback
│   │   ├── HudState.kt        Idle/Listening/Capturing/Processing/Answer/Logged/Error (+ BufferStatus chip) — mirrors webapp/
│   │   ├── Meal.kt            Prompts + tolerant meal-JSON parser
│   │   ├── Ports.kt           VlmEngine, Speaker, HudRenderer, MealLog, OnDemandCapture, Clock
│   │   ├── GlanceController.kt one turn: transcript → intent → frame → VLM → HUD + TTS (+ log)
│   │   └── HplBridge.kt       HP Lifestyle: pairing link, meal.logged event, HMAC-signed .hplevent, FileMealStore (persistent log)
│   ├── src/test/kotlin/glance/core/CoreTests.kt + HplTests.kt   72 checks
│   └── run-tests.sh
└── app/                       Android (DAT 1.0.1 + Mock Device Kit + LiteRT-LM 0.18.0). Compiles on the box (D0 ✅).
    └── src/main/kotlin/glance/app/
        ├── MainActivity.kt    debug console; voice invocations ("Hey Meta, start Glance") answered once
        ├── dat/GlassesRig.kt  DeviceSession → Display + Camera stream (2 fps MEDIUM → ring buffer) + Speech → controller
        ├── dat/DatHudRenderer.kt  HudState → display.sendContent { flexBox … } (info left, buttons right)
        ├── dat/YuvJpeg.kt     selected YUV frame → JPEG (I420 assumed; VERIFY)
        ├── debug/MockRig.kt   MockDeviceKit RBD + H.265 camera feed + test server :9000 + simulateTranscription + simulateLaunchAppAction
        ├── vlm/LiteRtVlmEngine.kt  Gemma 4 E4B, backend=GPU, visionBackend=GPU, Content.ImageBytes; CannedVlmEngine stand-in
        ├── audio/AndroidSpeaker.kt phone TTS → A2DP (not HFP)
        └── hpl/               HP Lifestyle bridge: HplActivity (pair + review + share .hplevent), PairingStore (Keystore), MealStoreHolder
```

Every API used in `app/` comes from Meta and Google docs pages linked in the file headers. Anything not confirmed on a reference page is marked `// VERIFY:`. Fix those first when you open the project against the real SDK.

## Run the core tests (works on any machine with JDK 17 + kotlinc)
```bash
phone/core/run-tests.sh      # last run 2026-10-11 02:50 PT: 72 passed, 0 failed (incl. 23 HP Lifestyle bridge)
# or: cd phone && ./gradlew :core:coreTests   (CI: .github/workflows/android.yml)
```

## Debug vs release layout
| Source set | Contents |
|---|---|
| `src/main` | Real loop: `GlanceGraph` (wiring), `GlassesRig`, `DatHudRenderer`, `LoggingHud`, `DevHooks` interface, `MainActivity` |
| `src/debug` | `MockRig` (Mock Device Kit), `DevHooksFactory` (auto-pairs mock RBD + debug buttons), `DebugCommandReceiver` + its manifest, `assets/mock_feed_hevc.mp4`, `assets/mock_photo_meal.jpg` |
| `src/release` | No-op `DevHooksFactory` → real glasses via `AutoDeviceSelector(isDisplayCapable)` |
| `src/androidTest` | `MockLoopTest` (4 tests, Mock Device Kit end-to-end), `HplBridgeTest` (2 tests: Keystore pairing, FileProvider export) |

`mwdat-mockdevice` is `debugImplementation` + `androidTestImplementation` only. Verified: release APK has 0 mockdevice/MockRig classes, no debug receiver, no mock assets.

## Mock startup (debug builds, no glasses, no registration)
`MainActivity` → `DevHooks.prepareDevice()` → `MockRig.startAndAwait()`:
1. `MockDeviceKit.enable(MockDeviceKitConfig(initiallyRegistered = true, initialPermissionsGranted = true))`. This skips Meta AI registration and the DAT camera permission prompt.
2. `pairGlasses(META_RAYBAN_DISPLAY)`, then `powerOn()`, `unfold()` and `don()`.
3. `setCameraFeed(file://…/cache/mock_feed_hevc.mp4)` and `setCapturedImage(file://…/cache/mock_photo_meal.jpg)`.
4. `startTestServer(9000)`.
5. **Waits until `Wearables.devicesMetadata[id].linkState == CONNECTED`** (15 s timeout). Only then does it return a `SpecificDeviceSelector(id)`. This fixes the pairing → session race.

Then `GlanceGraph.start()` opens the DAT session on that selector (Display + 2 fps Camera stream + Speech) and builds the controller.

### Mock camera media (bundled)
| File | What | Spec |
|---|---|---|
| `app/src/debug/assets/mock_feed_hevc.mp4` | Synthetic 9 s clip: desk (0–3 s) → **plate of grilled salmon, rice and broccoli with a text label** (3–7 s) → street crossing (7–9 s). Mild head-motion jitter; every 9th frame is blurred (exercises the sharpness picker) | **H.265, `hvc1` tag**, 504×896 portrait, 10 fps, yuv420p, 66 KB |
| `app/src/debug/assets/mock_photo_meal.jpg` | Still of the plate for the `capturePhoto` fallback | 504×896 JPEG, 49 KB |
| `docs/mock_feed_plate_frame.png` | Frame at 4.5 s, for reference | |

Generated with Pillow + `ffmpeg -c:v libx265 -crf 30 -pix_fmt yuv420p -tag:v hvc1` (libx265 is available on the box). The script is inline in the 2026-10-10 bot log, and is easy to regenerate.

Mock API constraints (from the DAT docs + javap of 1.0.1):
- **Android requires H.265/HEVC** for `setCameraFeed`.
- The argument is a `Uri`, so we copy the asset to `cacheDir` and pass `file://`. `file:///android_asset/` support is unverified.
- The feed presumably loops. VERIFY on first run: check frame timestamps in logcat.
- Mock speech is delivered only while `MockSpeechKit.isListening`, and `MockRig.say()` waits for that.
- The synthetic plate is cartoonish. Fine for wiring tests with `CannedVlmEngine`. For M1c quality checks, swap in a real food photo or clip.

## Bot-triggered turns (debug broadcast, no speech)
```bash
# NOTE: quote the whole remote command; adb shell re-splits argv, so --es text "what am I seeing" arrives as "what".
adb shell "am broadcast -a dev.arash.glance.DEBUG_COMMAND -n dev.arash.glance/glance.app.debug.DebugCommandReceiver --es text 'what am I seeing'"
adb shell "am broadcast ... --es intent describe"                          # or: log  (bypass router)
adb shell "am broadcast ... --es text 'log this meal' --ez viaMockSpeech true"  # MockSpeechKit → DAT Speech → controller
adb logcat -s GlanceHud:I GlanceDebug:I               # one line per HUD state: state=Answer text="…" meta="buffer · 0.4 s …"
tools/adb/smoke.sh ["what am I seeing"] [--via-mock-speech]   # launch + fire + assert; exit 0 = pass
```
The receiver is `exported` but requires `android.permission.DUMP`. The adb shell holds it; normal apps don't. It exists only in debug builds.

## Instrumented tests (`src/androidTest/kotlin/glance/app/MockLoopTest.kt`)
| Test | Asserts |
|---|---|
| `displayIdleShowsLiveBuffer` | Idle HUD rendered; mock H.265 stream fills the buffer (`origin = STREAM_BUFFER`) |
| `speechDescribeUsesBufferedFrame` | `MockRig.say("what am I seeing")` → HUD `Listening… → Capturing → Thinking → Answer`; meta starts with `pinned`/`buffer`; TTS called |
| `speechLogMealLogs` | "log this meal" → `Logged` |
| `debugCommandPathWithoutSpeech` | Receiver's code path → `Answer`, not `capture-fallback` |

**Result 2026-10-10: OK (4 tests)** on the box's software (TCG) emulator.

Run them on the box (no human):
```bash
tools/emu/tcg.sh up                                   # ≈3 min boot, API 29 x86_64, -accel off (KVM is forbidden on this box)
adb -s emulator-5554 install -r -g phone/app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 install -r -g phone/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s emulator-5554 shell am instrument -w -r -e timeoutScale 6 -e class glance.app.MockLoopTest dev.arash.glance.test/androidx.test.runner.AndroidJUnitRunner
SMOKE_SLOW=6 ANDROID_SERIAL=emulator-5554 tools/adb/smoke.sh "what am I seeing"
tools/emu/tcg.sh down
```
On a phone (D1):
```bash
source tools/env.sh && cd phone
./gradlew :app:connectedDebugAndroidTest          # builds + installs app & test APKs, runs, report in app/build/reports/androidTests/
# or, with APKs already installed:
adb shell am instrument -w -e class glance.app.MockLoopTest dev.arash.glance.test/androidx.test.runner.AndroidJUnitRunner
```
The test APK builds: `app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk` (1.3 MB).

## Chrome simulator preview (optional, human or bot browser)
`adb forward tcp:9000 tcp:9000` → `http://127.0.0.1:9000/` with the **Meta Ray-Ban Display Simulator** extension. Expect the Idle HUD chip `Live 2 fps · 0.x s`. Real model: build with `-Pglance.vlm=real` (or launch a debug build with `--es vlm real`) after `tools/m1c/push_model.sh`; see `docs/M1C_REAL_VLM.md`.

Bridge data shapes: `bridge-contract.json`.

## Build on the box (D0)
```bash
source tools/env.sh                     # from repo root: JDK 17, ANDROID_HOME=~/android-sdk, Gradle 8.14.3
cd phone && ./gradlew :core:build :app:assembleDebug :app:assembleRelease :app:assembleDebugAndroidTest     # → app/build/outputs/apk/debug/app-debug.apk (~84 MB, arm64-v8a + x86_64)
./gradlew --stop                         # free RAM afterwards (daemons capped at 2 GB / 1 GB in gradle.properties)
```

| Component | Version | Source |
|---|---|---|
| AGP | 8.13.2 | Google Maven |
| Kotlin | 2.4.21 | Maven Central |
| Gradle | 8.14.3 (wrapper) | services.gradle.org |
| compile/target SDK | 35 | sdkmanager |
| DAT | 1.0.1 (`mwdat-core/camera/display/speech`; `mwdat-mockdevice` as debugImplementation) | Maven Central |
| LiteRT-LM | 0.18.0 | Google Maven |
| coroutines | 1.11.0 | Maven Central |

Merged APK permissions: `BLUETOOTH_CONNECT`, `CAMERA`, `BLUETOOTH` (from DAT). **No INTERNET**, which supports the offline claim.

## Known runtime gaps (compile-clean, not yet run)
Fixed 2026-10-10:
- ✅ Mock in debug source set.
- ✅ Await mock CONNECTED.
- ✅ Bundled H.265 feed.
- ✅ ABI filter (arm64 + x86_64).
- ✅ Debug broadcast.
- ✅ androidTest scaffold.

Found and fixed by the first Android runs (TCG emulator, 2026-10-10; details in `docs/EMULATOR_ALTERNATIVES.md`):
- MDK test server EPERM: INTERNET added in the debug manifest only, server non-fatal.
- adb broadcast quoting.
- Negative frame age.
- DAT analytics/crash upload: opt-out meta-data in the main manifest.
- Test timeouts and `smoke.sh` re-runs.

Still open:
1. **No `Wearables.startRegistration` / permission flow for real glasses** (H6, M3). Mock skips both. **Verified** on the emulator: no Meta AI app needed.
2. `DatHudRenderer` uses `runBlocking` around the suspend `sendContent`. Worker thread only. On TCG each render takes 1.5–3 s, and it blocks the turn.
3. MDK Chrome preview server still fails to bind on the emulator (even with INTERNET). VERIFY on phone. HUD is asserted via `GlanceHud` logcat instead.
4. `simulateLaunchAppAction` not yet covered by a test.
5. Real Gemma inference (M1c) can't run on the TCG emulator (no GPU, 1.5 GB guest). Needs the phone (D1) or a cloud physical device. Wiring, flag, model (sha256 OK on the box) and `tools/m1c/run_real.sh` are ready (`docs/M1C_REAL_VLM.md`).
7. "Hey Meta, start Glance" is now bot-triggerable: `adb shell "am broadcast -a dev.arash.glance.DEBUG_COMMAND -n dev.arash.glance/glance.app.debug.DebugCommandReceiver --ez heyMeta true"` → logcat `GlanceDebug: heyMeta invocation=…` and MainActivity status `Hey Meta → Glance`. **Not yet run** on the emulator; a test assert is still TODO (gap 4).
6. Release APK is unsigned (fine for now).
