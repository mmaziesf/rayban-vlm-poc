# Glance: on-device VLM for Meta Ray-Ban Display (proof of concept)

Ask your glasses **"what am I seeing?"** or **"log this meal"**. A phone companion app takes a recent frame from a rolling buffer of the glasses camera stream. It runs **Gemma 4 E4B fully on-device** (LiteRT-LM, no network) and answers on the glasses HUD and by TTS.

Built on the [Meta Wearables Device Access Toolkit (DAT) 1.0.1](https://wearables.developer.meta.com/docs/develop/dat/getting-started-toolkit) for Android and iOS. Android is the primary platform; iOS is an optional port (milestone M7).

| | Android (`phone/`) | iOS (`ios/`) |
|---|---|---|
| Shared core logic | `phone/core` (pure Kotlin/JVM) | `ios/GlanceCore` (pure Swift) |
| App + DAT adapters | `phone/app` | `ios/GlanceApp` (SwiftUI, XcodeGen) |
| No-glasses testing | Mock Device Kit on emulator/phone, **4/4 instrumented tests pass** | Simulator: **fake-glasses UI tests 4/4 pass**; DAT mock link blocked (see below) |
| Real VLM | Wired: `-Pglance.vlm=real`, needs a physical GPU phone | Stub only (LiteRT-LM Swift is early preview) |
| CI | local scripts on the bot box | GitHub Actions [`ios` workflow](https://github.com/mmaziesf/rayban-vlm-poc/actions/workflows/ios.yml) |

Status, milestones and what is verified vs. not: **[`docs/MILESTONE_PLAN.md`](docs/MILESTONE_PLAN.md)**.

---

## Repository layout
```
phone/            Android app (Gradle): core/ (pure Kotlin) + app/ (DAT, LiteRT-LM, debug MockRig)   → phone/README.md
ios/              iOS: GlanceCore/ (SwiftPM, runs on Linux too) + GlanceApp/ (XcodeGen project)     → ios/README.md
webapp/           M1a web HUD prototype (for the Ray-Ban Display Chrome simulator)
tools/            env.sh, adb/ (phone link, deploy, smoke), emu/ (software emulator), m1c/ (model fetch/push/run)
infra/k8s/        Kubernetes manifests for a reproducible Android build/test stack
docs/             Plans, research, runbooks (see "Further reading")
.github/workflows/ios.yml   macOS CI for iOS
```

---

## Android

### Prerequisites
- JDK 17, Android SDK (platform 35, build-tools 35.0.0, platform-tools). Gradle comes from the wrapper (8.14.3).
- On the bot box everything is preinstalled: `source tools/env.sh` from the repo root.

### Build
```bash
source tools/env.sh
cd phone
./gradlew :core:build :app:assembleDebug                 # debug APK (Mock Device Kit included), stub VLM
./gradlew :app:assembleDebug -Pglance.vlm=real           # debug APK that loads Gemma 4 E4B if the model is on the device
./gradlew :app:assembleRelease                           # release APK: no mocks, no INTERNET permission (unsigned)
./gradlew :app:assembleDebugAndroidTest                  # instrumented test APK
./gradlew --stop                                         # free RAM afterwards
```
Output: `phone/app/build/outputs/apk/{debug,release,androidTest}/…`

### Unit tests (any machine, no device)
```bash
phone/core/run-tests.sh            # pure-Kotlin core: intents, ring buffer, controller, meal parser, VLM selection
```

### Emulator (no hardware)
The debug build auto-pairs a **mock Ray-Ban Display** (Mock Device Kit) and feeds it a bundled H.265 clip, so the full loop runs without glasses and without Meta AI registration.
```bash
tools/emu/tcg.sh up                # software (TCG) emulator, API 29 x86_64; ~3 min boot. On a normal dev machine any x86_64 AVD works.
adb -s emulator-5554 install -r -g phone/app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5554 install -r -g phone/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s emulator-5554 shell am instrument -w -r -e timeoutScale 6 -e class glance.app.MockLoopTest \
    dev.arash.glance.test/androidx.test.runner.AndroidJUnitRunner      # 4 tests
SMOKE_SLOW=6 ANDROID_SERIAL=emulator-5554 tools/adb/smoke.sh "what am I seeing"   # one end-to-end turn, exit 0 = pass
tools/emu/tcg.sh down
```
To trigger turns without speaking (debug builds), use the debug broadcast:
```bash
adb shell "am broadcast -a dev.arash.glance.DEBUG_COMMAND -n dev.arash.glance/glance.app.debug.DebugCommandReceiver --es text 'what am I seeing'"
adb logcat -s GlanceHud:I GlanceDebug:I GlanceVlm:I
```
The emulator always uses the **stub VLM**. It has no GPU delegate and too little RAM for Gemma, and the app falls back with a logged reason.

### Real phone (mock glasses) and real VLM
1. Connect the phone with USB or wireless adb. The bot uses `tools/adb/connect.sh pair …` / `connect.sh ensure` (Tailscale + adb over TCP; see [`docs/BOT_ADB_RUNBOOK.md`](docs/BOT_ADB_RUNBOOK.md)).
2. Run the mock loop on the phone:
   ```bash
   source tools/env.sh && cd phone && ./gradlew :app:connectedDebugAndroidTest
   tools/adb/deploy.sh                               # build + install + launch the debug app
   ```
3. Run real Gemma 4 E4B inference (milestone M1c; needs ~3.7 GB of storage and a GPU phone):
   ```bash
   tools/m1c/fetch_model.sh       # downloads gemma-4-E4B-it.litertlm (Apache-2.0, not gated), checks size + sha256
   tools/m1c/run_real.sh          # builds -Pglance.vlm=real, installs, pushes the model, runs N turns, prints p50/p90 latency
   ```
   Details: [`docs/M1C_REAL_VLM.md`](docs/M1C_REAL_VLM.md).

### Real glasses (Meta Ray-Ban Display)
One-time human steps (H1–H9 in [`docs/ON_DEVICE_DEBUGGING.md`](docs/ON_DEVICE_DEBUGGING.md)):
1. Pair the glasses in the **Meta AI** app.
2. Enable **Developer Mode** (Settings → App Info → tap the app version 5×).
3. Install a **release** (or debug) build. The release build uses `AutoDeviceSelector` to pick a real display-capable device.
4. Approve the Glance **registration** in Meta AI and the DAT **camera permission** when prompted. The bot never taps consent screens.

After that, the bot drives turns and measurements with adb (debug broadcast + logcat). The real-glasses flow (registration UI, M3) is **not yet implemented or verified**.

---

## iOS

### Prerequisites
- **GlanceCore:** any Swift 6 toolchain, on Linux or macOS.
- **GlanceApp:** a Mac with Xcode, plus `brew install xcodegen`.
  - Both are verified on CI: Xcode 16.4 (macos-15, the gate) and Xcode 26.6 (macos-26).
  - Meta's DAT samples state **Xcode 26.4+**, so prefer Xcode 26 locally.
- DAT 1.0.1 is pulled automatically as a Swift package (binary xcframeworks; iOS only). GlanceApp **cannot be built on Linux**.

### Core tests (Linux or macOS, no device)
```bash
ios/GlanceCore/run-tests.sh        # swift test; 11 XCTests
```

### Build and run in the Simulator
```bash
cd ios/GlanceApp
xcodegen                                       # generates GlanceApp.xcodeproj from project.yml
open GlanceApp.xcodeproj                       # Run on any iPhone simulator, Debug configuration
# or headless:
xcodebuild build-for-testing -project GlanceApp.xcodeproj -scheme GlanceApp \
  -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES
```
Simulator builds **must be ad-hoc signed** (`CODE_SIGN_IDENTITY=-`, as above and in `project.yml`). Unsigned builds have no keychain entitlement, so `Wearables.configure()` fails.

`project.yml` points at `Info.plist` with the `INFOPLIST_FILE` setting. **Don't switch it to XcodeGen's `info:` key**: that rewrites the plist with only default keys, dropping the `MWDAT` dict, URL scheme and Bonjour/Local Network keys. The DAT mock device then never connects. CI fails the build if the built app has no `MWDAT` dict.

Two Debug-only ways to run without glasses:
| Mode | How | What it exercises | Status on CI |
|---|---|---|---|
| **Fake glasses** | launch argument `--fake-glasses`, then tap **Start (mock)** | Real controller / intent router / frame buffer / HUD; synthetic frames, **no DAT link** | ✅ `FakeGlassesUITests` 4/4 (backup gate) |
| **DAT Mock Device Kit** | launch with `--ui-testing` (MockDeviceKit + test server start at launch), tap **Start (mock)**, then pair from the test via `MockDeviceTestClient.pairDevice()`, like Meta's CameraAccess tests. Without the flag, Start (mock) pairs in-process | DAT session, Camera, Speech, Display with a mock Ray-Ban Display | ✅ `MockLoopUITests` 4/4 on Xcode 16.4 and 26.6 (CI gate): mock device reaches `connected/compatible` |

UI tests:
```bash
UDID=<simulator udid from `xcrun simctl list devices available`>
xcodebuild test-without-building -project GlanceApp.xcodeproj -scheme GlanceApp -destination "id=$UDID" \
  -only-testing:GlanceAppUITests/MockLoopUITests -only-testing:GlanceAppUITests/FakeGlassesUITests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES
```
Debug triggers (the iOS equivalent of the Android broadcast):
```bash
xcrun simctl openurl booted 'glance-debug://command?text=what%20am%20I%20seeing'
xcrun simctl openurl booted 'glance-debug://command?text=log%20this%20meal&viaMockSpeech=true'
```

### Real iPhone and real glasses (not yet verified)
1. In Xcode, set your **Development Team** for the `GlanceApp` target. Drop the ad-hoc `CODE_SIGN_IDENTITY=-` / `CODE_SIGN_STYLE: Manual` overrides for device builds.
2. Fill the `MWDAT` keys in `Info.plist` (`META_APP_ID`, `CLIENT_TOKEN` build settings) as described in Meta's iOS integration docs. Developer Mode in Meta AI lets unpublished apps register.
3. Pair the glasses in Meta AI, enable Developer Mode, run the app on the iPhone, and approve registration and camera permission.
4. Real on-device VLM on iOS is **not implemented**: `OnDeviceVlmEngine` is a stub. Gemma 4 E2B is the likely target, because E4B vision is currently broken in LiteRT-LM iOS; see [`docs/IOS_OPTIONS.md`](docs/IOS_OPTIONS.md).

### CI (GitHub Actions)
[`.github/workflows/ios.yml`](.github/workflows/ios.yml) runs on every push:
| Job | What | Gating |
|---|---|---|
| `core-linux` | GlanceCore `swift test` on Ubuntu | yes |
| `app-simulator (xcode16)` | macos-15 / Xcode 16.4. GlanceCore, then XcodeGen + Simulator build (with a check that the built Info.plist has `MWDAT`), then `MockLoopUITests` (DAT MockDeviceKit link) and `FakeGlassesUITests`, plus a `--mock-probe` diagnostic. Uploads xcresult, crash reports and the app log | yes |
| `app-simulator (xcode26)` | Same steps on macos-26 / Xcode 26.6 | no (experimental) |

Both legs pass the DAT mock tests 4/4 (run [38126000773](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38126000773)). The history of the former mock-link blocker is in [`docs/IOS_OPTIONS.md`](docs/IOS_OPTIONS.md).

---

## Further reading
| Doc | Topic |
|---|---|
| [`docs/MILESTONE_PLAN.md`](docs/MILESTONE_PLAN.md) | Milestones M1–M7, tiers, current status |
| [`docs/MILESTONE1_RESEARCH.md`](docs/MILESTONE1_RESEARCH.md) | DAT / Gemma / platform research |
| [`docs/STREAMING_BUFFER.md`](docs/STREAMING_BUFFER.md) | 2 fps stream + rolling buffer design |
| [`docs/M1C_REAL_VLM.md`](docs/M1C_REAL_VLM.md) | Real Gemma 4 E4B on Android |
| [`docs/ON_DEVICE_DEBUGGING.md`](docs/ON_DEVICE_DEBUGGING.md), [`docs/BOT_ADB_RUNBOOK.md`](docs/BOT_ADB_RUNBOOK.md) | Phone/glasses debugging, one-time human steps |
| [`docs/EMULATOR_ALTERNATIVES.md`](docs/EMULATOR_ALTERNATIVES.md), [`docs/K8S_ANDROID_ENV.md`](docs/K8S_ANDROID_ENV.md) | Emulator options, Kubernetes build/test stack |
| [`docs/IOS_OPTIONS.md`](docs/IOS_OPTIONS.md) | iOS options, CI history, mock-link root cause |
| [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md) | Open questions |
| [`phone/README.md`](phone/README.md), [`ios/README.md`](ios/README.md), [`webapp/README.md`](webapp/README.md) | Component details |
