# iOS companion: options, blockers, recommendation (M7)

_2026-10-10 · written by the bot on the Linux box. Ran = ✅, written but not run = 📝._

## Update 2026-10-10 22:45 PT: CI green on an honest fallback gate; DAT mock link still blocked
**CI now:** `app-simulator` is green and the gate is real:
- GlanceCore: 11/11 on Linux and macOS.
- GlanceApp: builds for the Simulator.
- **`FakeGlassesUITests` 4/4 ✅** (first passing iOS UI tests). Run [38114488227](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38114488227).

`MockLoopUITests` (DAT MockDeviceKit link) still runs on every push, as a **non-gating** step, and is still 0/4.

What the fake-glasses suite covers, and what it doesn't:
- `--fake-glasses` (DEBUG) starts **no DAT session**. `FakeRig` pushes synthetic 504×896 luma frames at 2 fps into the real `FrameRingBuffer`.
- The real `GlanceController` / `IntentRouter` / `BufferedFrameSource` / `HudState` → phone HUD run end to end, driven through the UI.
- Tests: idle shows a Live buffer; the "what am I seeing" command answers; spoken describe answers (partial → final transcript); spoken "log this meal" → Logged.
- It does **not** test DAT Camera/Speech/Display or the glasses link. Those stay in `MockLoopUITests`, and later on a real iPhone (T2).

**Bug found while building the fallback:** the iOS `CannedVlmEngine` returned `{"food":true,…}`, but `MealParser` requires `"is_food"`. So "log this meal" could never reach Logged on iOS. Fixed, with a regression test (`CannedMealContractTests`).

**Mock-link attempts in this round (all ❌, same symptom: the device is listed, `linkState` stays `disconnected`, `compatibility` stays `undefined`):**
| # | Attempt | Run | Result |
|---|---|---|---|
| 1 | `powerOn → unfold → don` (BirdSpotter) + `devicesStream()` subscribed from launch | [38112910442](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38112910442) | UI 0/4, link `disconnected/undefined` for 10 s |
| 2 | Pair + powerOn/unfold/don in `Task.detached`; `addLinkStateListener` + `addCompatibilityListener` | [38113596903](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38113596903) | UI 0/4. Listeners fire **once** (`disconnected`, `undefined`) and never again |
| 3 | `--mock-probe` (DEBUG, launched by CI after the tests, not counted as tests) tried 4 variants for 8 s each: main-actor, detached + listener, **`.rayBanMeta`**, no-arg `MockDeviceKit.enable()` | 38113596903 (Diagnostics step) | all 4: `connected=false link=disconnected compat=undefined devices=1`. **Not RBD-specific, not threading** |
| 4a | `keychain-access-groups` entitlement like Meta's samples | [38114488227](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38114488227) | no change |
| 4b | Control: Meta's CameraAccess XCUITest on the same runner | 38114488227 | **did not compile**: the samples on `main` need **Xcode 26.4+** (`isolated deinit`); `app-simulator` uses the macos-15 default **Xcode 16.4** |
| 4c | Control on `macos-26` + newest Xcode 26: Meta CameraAccess mock-pair test **and** our MockLoopUITests | [38115170427](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38115170427) | pending at 22:55 PT |

**Leading hypothesis:** Xcode/SDK mismatch. DAT 1.0.1 is built for, and its samples documented against, Xcode 26.4+. We link it from Xcode 16.4. It compiles and configures, but the mock link may depend on newer runtime behaviour. Run 4c tests this directly.

## Update 2026-10-10 21:50 PT: mock-start crash fixed; UI tests still 0/4 (link never connects)
| Run | Commit | Result | Finding |
|---|---|---|---|
| [38108083323](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38108083323) | 3d483b9 | build ✅, UI 0/4 | Crash report captured: `EXC_BREAKPOINT` / `_assertionFailure` inside MWDATCore at the first `Wearables.shared` access (GlanceApp.swift:63) |
| [38109145843](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38109145843) | 45d2c7a | build ✅, UI 0/4 | Streamed app log: `Wearables.configure()` → `WearablesError.internalError`, right after Security `-34018 "Client has neither application-identifier nor keychain-access-groups entitlements"`. **Root cause:** CI built with `CODE_SIGNING_ALLOWED=NO` |
| [38109885287](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38109885287) | a33aceb | build ❌ | Signing on → UI-test target needs `GENERATE_INFOPLIST_FILE` |
| [38110449565](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38110449565) | c1f1f98 | build ❌ | Runner image had no "iPhone 16" simulator (infra) → CI now builds for `generic/platform=iOS Simulator` and picks or creates an iPhone by UDID |
| [38110641886](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38110641886) | 1a8547e | build ✅, UI 0/4, **no crash** | `configure ok=true`, MDK enable + pair OK; link stays `disconnected`, compat `undefined` → clean `Start failed` on HUD |
| [38111400016](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38111400016) | 9b6f73d | build ✅, UI 0/4 | Sample order (powerOn → don), soft wait → session `noEligibleDevice`; `Wearables.devices == []` |
| [38112144196](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38112144196) | ad06c9a | build ✅, UI 0/4 | `devicesStream()` now subscribed: the device **is listed**, but stays `disconnected/undefined` for 10 s → `noEligibleDevice` |

**Fixed:**
1. The app no longer crashes. `DatBoot` records configure errors and guards every `Wearables.shared` access; errors show on the HUD and in the UI-test failure text.
2. DAT configures on the Simulator, via ad-hoc "Sign to Run Locally" signing.
3. CI is honest:
   - pipefail on;
   - the build is a gate;
   - UI tests are a gate (the run is red when they fail);
   - an always-run diagnostics step dumps the xcresult summary, crash `.ips` files and the streamed `GlanceDiag` app log;
   - the simulator is chosen by UDID.

**Remaining blocker:** the paired mock Ray-Ban Display never reaches `linkState == .connected` / `compatibility == .compatible` on the CI Simulator, so `createSession` → `noEligibleDevice`. GlanceCore stays green (10/10 Linux + macOS).

**Candidates at 21:50 PT (all tried at 22:45 PT; see the update above):**
1. `powerOn → unfold → don` **with** devicesStream subscribed. BirdSpotter does unfold; run 38110641886 had unfold but no subscription.
2. Pair off the main actor (`Task.detached`, as BirdSpotter does: "pairing is the SDK's own work"), and add `device.addLinkStateListener`.
3. Try `.rayBanMeta` (CameraAccess) to see if it's RBD-specific.
4. Build and run Meta's own DisplayAccess sample on the same runner as a control.
   - If its mock also stays disconnected, the problem is the runner/Simulator (e.g. a Bluetooth/LAN-backed mock link), not our code.
   - Fallback: run the controller-level flow with `MockDeviceKitConfig` + a fake `DeviceSelector`-free path (camera frames from the bundled clip) so the HUD/intent UI tests can pass without DAT link.

## Update 2026-10-10 20:00 PT: first macOS CI run
- **Repo:** https://github.com/mmaziesf/rayban-vlm-poc · **run:** https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38106506396 (commit `953c3ee`; both jobs reported ✅)
- **Actually verified by that run:**
  - `core-linux` 10/10.
  - macOS `GlanceCore` 10/10.
  - **`GlanceApp` (SwiftUI + DAT 1.0.1 SPM + MockDeviceKit) type-checks and builds for the iOS Simulator.** This upgrades it from "structural only" to **compiles**; only Swift 6 Sendable warnings, e.g. capture of non-Sendable `GlanceController`.
- **Not passing:** `MockLoopUITests` **0/4**. Every test timed out in `setUp` waiting for the status "Mock glasses connected", so the app's start path (MDK enable → pair → session) did not reach "connected" on the Simulator.
  - The job still showed green because `xcodebuild test | tee` lost the exit code.
  - **Fixed in the workflow:** `set -o pipefail`; split into a `build-for-testing` gate plus a `test-without-building` step marked `continue-on-error`, so it is visible as failing; upload the `.xcresult`.
  - The test now prints the app's actual status label (e.g. `Start failed: …`).
- **Run 2:** https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38107229753 (commit `52e3b3c`, with the fixed workflow).
  - `** TEST BUILD SUCCEEDED **`, then `** TEST EXECUTE FAILED **`: UI tests still 0/4.
  - The new diagnostic shows `status was: '<missing>'` in all 4 tests, and XCTest logged "Checking for crash reports corresponding to **unexpected termination** of dev.arash.GlanceApp" right after `Tap "startMock"`.
  - So the app **crashes on mock start**; it is not just slow to connect. The crash report wasn't recoverable from the `.xcresult` on Linux.
  - Next: add an `xcrun xcresulttool` / `~/Library/Logs/DiagnosticReports/*.ips` dump step on the macOS runner, and wrap `MockDeviceKit.enable`/`pairGlasses` and `Wearables.configure()` with logged errors.
- **Next iOS fix candidates:**
  1. Wait for the link to be CONNECTED instead of sleeping 0.5 s.
  2. Use a `SpecificDeviceSelector` for the mock device instead of `AutoDeviceSelector`.
  3. Check whether `Wearables.configure()` threw on the Simulator.

## TL;DR — is iOS possible on this box?
**Only partly.**
- **✅ Runs here:** the platform-neutral Swift core, `ios/GlanceCore`. It covers intents, the rolling frame buffer, frame selection, the controller and meal parsing. It builds and **passes 10/10 XCTests** with the Linux Swift 6.4 toolchain.
- **❌ Cannot run here:** the iOS app itself, in either Simulator or device form.
  - Xcode and the iOS Simulator exist only on macOS.
  - Meta DAT for iOS ships as **binary `.xcframework`s only** (slices `ios-arm64`, `ios-arm64_x86_64-simulator`), so it can't be linked, or even type-checked, against Linux.
  - Running macOS in a VM on this box is ruled out on two counts. It would need `/dev/kvm`, which is banned here after the nested-KVM kernel BUG. And Apple's EULA allows macOS VMs only on Apple hardware.
- **📝 Structural only:** `ios/GlanceApp`. It has a SwiftUI app, DAT adapters, a debug MockRig, XCUITests, an XcodeGen spec and a CI workflow. It was written against the DAT 1.0.1 `.swiftinterface` files and passes `swiftc -parse` (syntax only), but it has **never been type-checked, built or run**.
- **Cheapest real path:** run it on a GitHub-hosted macOS runner. Minutes are free if the repo is public. The one-time ask is that the user creates or pushes a GitHub repo, or authorises the bot's GitHub MCP, which currently shows `needsAuth`.

## Ranked options
| # | Option | Runs the app? | DAT MockDeviceKit? | Cost | One-time user input | Bot-autonomous after setup? | Status |
|---|---|---|---|---|---|---|---|
| 1 | **Linux box: Swift core + XCTest** | No (core only) | No | 0 | none | Yes | ✅ **10/10 PASS** |
| 2 | **GitHub Actions `macos-15` runner**: `xcodegen` + `xcodebuild test` on the iOS Simulator with the MockDeviceKit XCUITests | Yes (Simulator) | Yes. The MDK is designed for Simulator plus XCUITest via `MockDeviceTestClient` | Free for public repos; macOS $0.062/min on private repos | A GitHub repo, plus GitHub auth for the bot (MCP is `needsAuth`; or `gh auth` token); the user picks public or private | Yes. Push, poll the run, read logs/artifacts | 📝 `.github/workflows/ios.yml` written, **not run** |
| 3 | **AWS EC2 Mac** (mac2.metal etc.), reached over SSH from the box | Yes (Simulator; no real iPhone) | Yes | Dedicated host, **24 h minimum** (~$26+/day) | AWS account + keypair; allocate a dedicated host | Yes over SSH | not attempted |
| 4 | **MacStadium / other hosted Mac** (monthly) | Yes | Yes | Monthly rental | Account + SSH credentials | Yes over SSH | not attempted |
| 5 | **Appetize.io**: upload a Simulator `.app` (zip), interactive or API session in the browser | Yes (hosted Simulator) | Yes (MDK is in-app) | Free tier / paid | Account + API key; **still needs a Mac (#2–4) to build the `.app`** | Partly (REST upload; scripted UI is limited) | not attempted |
| 6 | **BrowserStack App Automate (XCUITest)**: `.ipa` + test-runner zip on **real iPhones** | Yes (real device, but no Meta glasses or Meta AI app) | Yes (MDK) | Paid / trial | Account + access key; **needs a Mac to build a signed `.ipa`**; BrowserStack re-signs | Yes over REST | not attempted |
| 7 | User's own Mac + iPhone + glasses (D1-iOS) | Yes (real glasses) | Real DAT | 0 | Mac, Apple Team ID, MetaAppID/ClientToken (Wearables Developer Center), Meta AI app pairing | No (iOS has no adb; needs `xcrun devicectl` on the Mac) | — |
| ✗ | Docker-OSX / OSX-KVM (macOS in QEMU on Linux) | — | — | — | — | — | **Blocked**: needs `/dev/kvm` (banned here after the kernel BUG), and **Apple's EULA allows macOS VMs only on Apple hardware**. TCG without KVM would be far too slow |
| ✗ | Xcode/Simulator on Linux, Darling, "containerized iOS" | — | — | — | — | — | **Not possible**: no Simulator runtime outside macOS; Darling can't run Xcode/Simulator. There is no redroid-style container for iOS |

**Recommendation:** use #2, GitHub Actions macOS.
- It is the only path that is near-free, needs no new hardware, and lets the bot run the PLAN/BUILD/TEST/FIX loop by itself: push → `xcodebuild test` → read logs.
- DAT's MockDeviceKit plus `MockDeviceTestClient` were built for exactly this Simulator + XCUITest flow.
- Fall back to #3 only if the repo must be private and minutes run high.
- Use #7 for real-glasses milestones (M3-iOS).

### What the user must provide once (for #2)
1. A GitHub repo for `rayban-vlm-poc`. Public means free macOS minutes; private bills macOS minutes.
2. Bot access to that repo, by either:
   - connecting the GitHub integration (cursor-github MCP is currently `needsAuth`), or
   - a fine-grained PAT scoped to that repo (contents + actions read/write) in `gh auth login` on the box.

Nothing else is needed for the Simulator/MDK tier. No Apple account is needed while `CODE_SIGNING_ALLOWED=NO` is set for the Simulator.

## Bot loop once #2 exists
`ios/GlanceCore/run-tests.sh` (local) → `git push` → `gh run watch` → `gh run view --log-failed` / artifact `xcodebuild.log` → fix → repeat.
- The UI tests assert `hudLabel` reaches `Ready` / `Answer` / `Logged`, the same assertions as Android `MockLoopTest`.
- Debug trigger, the iOS equivalent of `am broadcast`: `xcrun simctl openurl booted 'glance-debug://command?text=what%20am%20I%20seeing'`. Add `&viaMockSpeech=true` to route through `MockSpeechKit.simulateTranscription`.

## DAT Android ↔ iOS mapping (1.0.1)
| Concern | Android (used in `phone/`) | iOS (used in `ios/GlanceApp`, from `.swiftinterface`) |
|---|---|---|
| Init | `Wearables.initialize(ctx)` | `try Wearables.configure()`; `Wearables.shared` |
| Session | `Wearables.createSession(SpecificDeviceSelector(id))` | `try Wearables.shared.createSession(deviceSelector: AutoDeviceSelector(wearables:))`; `try session.start()`; `stateStream()` (idle/starting/started/paused/stopping/stopped) |
| Camera stream | `addCamera(StreamConfiguration(RAW, MEDIUM, fps))` | `session.addCamera(config: StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 2))`; `camera.stream.videoFramePublisher.listen { $0.sampleBuffer }`; `stream.start()` |
| On-demand photo | `capturePhoto(JPEG)` | `stream.capturePhoto(format: .jpeg)` → `stream.photoDataPublisher` (`PhotoData.data`); hi-res via `camera.photo.capturePhoto(resolution:quality:)` |
| Display HUD | `addDisplay()` + flexbox views | `session.addDisplay()`; `display.start()`; `try await display.send(FlexBox { Text(_, style: .heading/.body/.meta, color:) })` |
| Speech | `addSpeech()`; `transcriptions` | `session.addSpeech()`; `speech.transcriptionPublisher` (`text`, `isFinal`, `confidence`); `start()`/`stop()` |
| Mock kit | `MockDeviceKit.enable(MockDeviceKitConfig(true,true))`; `pairRayBanDisplay()` | `MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered:initialPermissionsGranted:))`; `pairGlasses(model: .metaRayBanDisplay)`; `powerOn/unfold/don` |
| Mock feed | `services.camera.setCameraFeed(uri)` (H.265) | `services.camera.setCameraFeed(fileURL:)`, `setCapturedImage(fileURL:)`. The **same** `mock_feed_hevc.mp4` / `mock_photo_meal.jpg` are copied to `ios/GlanceApp/Resources/` |
| Mock speech | `services.speech.simulateTranscription` | `services.speech.simulateTranscription(text:isFinal:confidence:)` |
| Test driver | instrumented test + MDK in-process | **`MockDeviceTestClient(port:)`** from XCUITests ↔ in-app `MockDeviceKit.shared.startTestServer(port:)` |
| Telemetry opt-out | manifest `com.meta.wearable.mwdat.ANALYTICS_OPT_OUT` / `CRASH_REPORTING_OPT_OUT` | Info.plist `MWDAT > Analytics > OptOut = true`, `MWDAT > CrashReporting > OptOut = true` (done in `Info.plist`) |
| App config | manifest meta-data | Info.plist `MWDAT`:<br>• `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, `TeamID` (Developer Mode accepts an empty or `0` MetaAppID)<br>• `UISupportedExternalAccessoryProtocols = com.meta.ar.wearable`<br>• background modes |
| Bot trigger | `adb shell am broadcast … DEBUG_COMMAND` | `xcrun simctl openurl booted glance-debug://command?...` (DEBUG only) |

## On-device VLM on iOS
- **LiteRT-LM Swift API is "Early Preview"** (Metal GPU). Google lists Gemma 4 E4B on iPhone 17 Pro at ~1189 tok/s prefill / ~25 tok/s decode (GPU).
- **However, E4B vision currently fails on iOS LiteRT-LM v0.12.0** (issue #2370) while E2B works, so **plan on Gemma 4 E2B for iOS** until that is fixed.
- Alternative: MLX Swift port (`gemma-4-swift-mlx`), which targets Apple Silicon.
- In the scaffold, `OnDeviceVlmEngine` intentionally throws `NotWired`; tests use `CannedVlmEngine`. No iOS VLM API was compiled or verified from Linux.

## What was built
| Path | What | Verified |
|---|---|---|
| `ios/GlanceCore/` | SwiftPM package that ports `core/`:<br>• `IntentRouter` (same regexes; curly apostrophes)<br>• `FrameRingBuffer` (capacity 6, sharpest-of-3, pin)<br>• `BufferedFrameSource` (pinned → buffer → capture → none)<br>• `GlanceController` (incl. the frame-age clamp fix)<br>• `Prompts` / `MealParser` | ✅ `run-tests.sh`: **10/10 XCTest pass** (Swift 6.4, Linux) |
| `ios/GlanceApp/Sources/DAT/GlassesRig.swift` | Session + camera (raw/medium/2 fps → CVPixelBuffer luma → buffer) + speech + display; JPEG on-demand capture fallback | 📝 parse-only |
| `ios/GlanceApp/Sources/DAT/DatHudRenderer.swift` | HudState → DAT FlexBox; `TeeHud` logs `GlanceHud: state=…` like Android | 📝 parse-only |
| `ios/GlanceApp/Sources/Engines/Engines.swift` | `CannedVlmEngine`, `OnDeviceVlmEngine` stub, `AVSpeaker`, `InMemoryMealLog` | 📝 parse-only |
| `ios/GlanceApp/Sources/App/GlanceApp.swift` | SwiftUI app; `GlanceModel` graph on a serial queue; `glance-debug://` URL trigger | 📝 parse-only |
| `ios/GlanceApp/Debug/MockRig.swift` | `#if DEBUG` MDK rig: pair RBD, power/unfold/don, same H.265 feed, `say()`, test server :9000 | 📝 parse-only |
| `ios/GlanceApp/UITests/MockLoopUITests.swift` | 4 XCUITests mirroring Android `MockLoopTest` | 📝 parse-only |
| `ios/GlanceApp/project.yml`, `Info.plist` | XcodeGen spec (DAT SPM 1.0.1 + local GlanceCore); MWDAT keys incl. telemetry opt-out | YAML/plist syntax ✅ |
| `.github/workflows/ios.yml` | Linux core job + macOS Simulator build/UI-test job | YAML ✅, **not run** |

### Known gaps / things to verify on first macOS build
- **MockRig link wait.** `MockRig` waits a fixed 0.5 s rather than waiting for `LinkState.connected`, the way Android does. It should use `addLinkStateListener` / `devicesStream`.
- **UI-test device id.** The UI tests call `client.pairDevice(...)` to get a device id. That likely pairs a *second* mock device. The in-app device id should be exposed to the tests instead, e.g. via an accessibility label.
- **Camera capability.** `GlassesRig.lumaFrame` assumes the raw stream arrives as a bi-planar YUV (or BGRA) `CVPixelBuffer`. This is unverified.
- **VLM input.** The VLM needs RGB/JPEG; the buffer currently holds luma only (TODO).
- **Mock assets in Release.** `Resources/mock_*` would ship in Release builds; they should be excluded from Release.
- **Swift 6 concurrency.** Strict-concurrency warnings and errors are likely on the first Xcode build, because the `@Sendable` closures capture `self` and the controller. This is expected fix-up work.

## Bugs / fixes during this milestone
- **`swift test` couldn't locate `swiftc`.** SwiftPM 6.4's new default build system resolved `swiftc` relative to the package directory with the swift.org Linux tarball layout. Clean env and absolute paths didn't help. **Fix:** `--build-system native`, wrapped in `ios/GlanceCore/run-tests.sh`. It prints a deprecation warning only.
- **DAT `Text` styles.** These are `.heading/.body/.meta`, not `.title/.caption`. This was caught by reading the `.swiftinterface` and fixed before parse.
- **Info.plist keys.** Aligned with DAT `AGENTS.md`: `processing` background mode, `NSLocalNetworkUsageDescription`, `NSBonjourServices`.

## Sources
- DAT iOS SDK: https://github.com/facebook/meta-wearables-dat-ios (README: telemetry opt-out; `AGENTS.md`: Info.plist keys; CHANGELOG 1.0.1), API reference: https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest, MDK testing: https://wearables.developer.meta.com/docs/testing-mdk-ios
- LiteRT-LM: https://developers.google.com/edge/litert-lm/overview · E4B iOS vision bug: https://github.com/google-ai-edge/LiteRT-LM/issues/2370 · MLX alt: https://github.com/VincentGourbin/gemma-4-swift-mlx
- GitHub Actions billing / runners: https://docs.github.com/en/billing/concepts/product-billing/github-actions · https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- AWS EC2 Mac 24 h minimum: https://github.com/petems/aws-mac-runner
- Appetize (Simulator `.app` zip only; no IPA): https://docs.appetize.io/platform/app-management/uploading-apps/ios
- BrowserStack XCUITest (real iPhones; `.ipa` + runner zip): https://www.browserstack.com/docs/app-automate/xcuitest/getting-started
- macOS-in-Docker and licensing: https://github.com/sickcodes/Docker-OSX/blob/master/FAQ.md · Apple macOS SLA: https://www.apple.com/legal/sla/docs/macOSTahoe.pdf
