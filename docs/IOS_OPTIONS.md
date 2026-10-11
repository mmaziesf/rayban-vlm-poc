# iOS companion: options, blockers, recommendation (M7)

_2026-10-10 · written by the bot on the Linux box. Ran = ✅, written but not run = 📝._

## Update 2026-10-11 02:15 PT: ROOT CAUSE FOUND. DAT mock link works; MockLoopUITests 4/4 and now gating
**Root cause:** `ios/GlanceApp/project.yml` used XcodeGen's `info: { path: Info.plist }` with no `properties`.
- XcodeGen **rewrites** that file on every generation. Its output is ~8 default keys (`CFBundle*`) plus `properties` (XcodeGen `FileWriter.writePlists`).
- So our checked-in plist, with the `MWDAT` dict (AppLinkURLScheme…), `CFBundleURLTypes`, `NSBonjourServices`, `NSLocalNetworkUsageDescription`, Bluetooth keys and `UIBackgroundModes`, **never reached the built app**.
- In that state DAT 1.0.1 registers, pairs and lists the mock device, but it stays `disconnected/undefined`: `AutoDeviceSelector` never yields → `noEligibleDevice`.
- It also explains why every earlier "Info.plist experiment" changed nothing: those keys were never in the build.

**Fix (commit ad3803d):**
- `INFOPLIST_FILE: Info.plist` in target settings, so the plist is used as-is.
- The CI build step now fails if the built `GlanceApp.app/Info.plist` has no `MWDAT.AppLinkURLScheme`.

**Result, run [38126000773](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38126000773):**
| Leg | Built plist MWDAT | MockLoopUITests (DAT mock) | FakeGlassesUITests |
|---|---|---|---|
| xcode16 (macos-15, Xcode 16.4) | ✅ `glance://` | ✅ **4/4** | ✅ 4/4 |
| xcode26 (macos-26, Xcode 26.6, iOS 26.5) | ✅ | ✅ **4/4** | ✅ 4/4 |

The app log shows `connecting/undefined` → **`connected/compatible`** and "Mock glasses connected". Before the fix, every run showed `disconnected/undefined`.

**How it was found (bisect with a minimal probe app, `ios/MockProbe`, since removed):**
| Run | Variant | Result |
|---|---|---|
| [38122289140](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38122289140) | ProbeLite = sample's products only (Core+Camera+MockDevice), sample's Info.plist *file*, Swift 6, iOS 17.2, test-client `pairDevice()` | ❌ same `disconnected/undefined` → **Display/Speech linkage ruled out** |
| [38123091432](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38123091432) | ProbeLite with the sample's bundle id; ProbeFull; Meta CameraAccess unmodified **and** with our-style bundle id | probes ❌; sample ✅ both → **bundle id ruled out** |
| [38124564513](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38124564513) | Touching `MockDeviceKit.shared` before `Wearables.configure()` (as CameraAccessApp's stored property does), in GlanceApp and ProbeLiteEarly. Parallel testing on a simulator **clone** (probes with `-parallel-testing-enabled YES`; sample with `NO`) | GlanceApp ❌ 0/4 both legs; ProbeLiteEarly ❌; ProbeLite/Full on clones ❌; sample serial ✅ → **init order and clone vs booted device ruled out** (early touch reverted) |
| [38126000773](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38126000773) | Info.plist via `INFOPLIST_FILE` (GlanceApp + probes) | ✅ GlanceApp 4/4 + 4/4 on both legs. ProbeLite and ProbeFull both active + `connected/compatible`; ProbeFull session `started`; ProbeLite's session start timed out after going active (probe only, not investigated) |

At that point the probes still differed from the sample only in *project generator*. Reading XcodeGen's source showed the plist rewrite.

**CI now:**
- Gate on **both** matrix legs (Xcode 16.4 and 26.6): GlanceCore + build (+ plist check) + **MockLoopUITests** + FakeGlassesUITests (backup gate, runs even if the mock step fails).
- Follow-up race fix: run [38126926753](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38126926753) went 3/4 on Xcode 26 (`testSpeechDescribeUsesBufferedFrame`: "session did not reach .started (state=started)"). `stateStream()` doesn't replay the current state, so `.started` could arrive between the check and the subscription. `GlassesRig.waitForStarted` now also polls `session.state`.
- Second race, run [38128195912](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38128195912), Xcode 16.4, `testSpeechLogMealLogs`: status was `session state: started` instead of "Mock glasses connected". Rig progress hops to the main actor asynchronously and could overwrite the final status. Fix: after the app reports connected, rig progress is log-only, except session errors and `stopped`.
- The `mock-bisect` job and `ios/MockProbe` are removed.
- **Still open:** real iPhone + glasses, and the iOS on-device VLM (stub).

## Update 2026-10-11 01:50 PT: test-process pairing (CameraAccessUITests pattern) — still 0/4 on both Xcodes
Run [https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38121054364](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38121054364), commit d39cb4c. Overall ✅ green (gate unchanged).

| Leg | Fake-glasses gate | MockLoopUITests |
|---|---|---|
| xcode16 (macos-15, Xcode 16.4, iOS 26.2) | ✅ 4/4 | ❌ 0/4 |
| xcode26 (macos-26, Xcode 26.6, iOS 26.5) | ✅ 4/4 | ❌ 0/4 |

What was implemented (now the default `MockLoopUITests` flow):
1. Launch with `--ui-testing` + `MWDAT_TEST_SERVER_PORT_FILE`.
   - `DatBoot` runs `Wearables.configure()`, then `MockDeviceKit.enable(initiallyRegistered: false)` + `startTestServer(portFilePath:)`.
   - Only after that does it subscribe to devices. This is the same order as `CameraAccessApp.init`.
2. The test calls `MockDeviceTestClient.waitForServer` ✅.
3. The test taps Start (mock). The app calls `startRegistration()` → registered ✅ and shows "Waiting for test-paired glasses".
4. The test calls `client.pairDevice(deviceType: .metaRayBanDisplay)` → id returned ✅. The device appears in `Wearables.shared.devices` ✅.
5. The app waits up to 90 s × timeoutScale on `AutoDeviceSelector.activeDeviceStream()`.
   - ❌ It never yields.
   - The device stays `disconnected/undefined` → "mock device not ready".

**Exact remaining differences vs Meta's CameraAccess sample (whose session-start test passes on macos-26 CI):**
| | CameraAccess | GlanceApp |
|---|---|---|
| DAT products linked | MWDATCore, **MWDATCamera**, MWDATMockDevice (+ TestClient in UI tests) | MWDATCore, MWDATCamera, **MWDATDisplay, MWDATSpeech**, MWDATMockDevice (+ TestClient) |
| Mock model paired by the test | `pairDevice()` default `.rayBanMeta` | `.metaRayBanDisplay` (in-process probe with `.rayBanMeta` also failed, but never via the test client) |
| Swift language mode / deployment target | Swift 6.0 / iOS 17.2 | Swift 5 (XcodeGen default) / iOS 17.0 |
| `MockDeviceKitConfig` | `initiallyRegistered: false` | `initiallyRegistered: false, initialPermissionsGranted: true` |
| Info.plist | `audio` background mode, scene manifest, `UIRequiredDeviceCapabilities arm64`; no ExternalAccessory | ExternalAccessory protocol + mode (removing them: no change, run 38119977792) |
| Bundle id / project | `com.meta.wearables.external.CameraAccess`, hand-made .xcodeproj | `dev.arash.GlanceApp`, XcodeGen |
| Already matched (no effect) | ad-hoc signing, keychain entitlement, Xcode 26, registration flow, AutoDeviceSelector, test-server pairing, pairing order, off-main pairing | |

**Most likely next step (not tried):** the extra **MWDATDisplay/MWDATSpeech** linkage. `compatibility` stays `undefined`, which suggests that capability modules registered at launch change how the mock device's compatibility is evaluated.

Cheapest check: a build variant (or a second tiny app target) linking only Core + Camera + MockDevice, running the same test flow with `pairDevice()` default `.rayBanMeta`. If that connects, add modules back one by one. Second option: build CameraAccess with MWDATDisplay + MWDATSpeech added, to see whether it breaks.

**Parked** per decision: the gate stays GlanceCore + build + `FakeGlassesUITests` (Xcode 16.4); MockLoopUITests stay non-gating on both legs.

## Update 2026-10-11 00:55 PT: Xcode 26 builds; DAT mock still 0/4 on macos-26 (final blocker for now)
**CI now** (`app-simulator` matrix; GlanceCore 11/11 + build + `FakeGlassesUITests` gate in both legs):
| Leg | Runner / toolchain | Build | FakeGlassesUITests | MockLoopUITests (DAT MockDeviceKit) |
|---|---|---|---|---|
| `xcode16` (**gate**) | macos-15, Xcode 16.4, iOS 26.2 sim | ✅ | ✅ 4/4 | ❌ 0/4 (non-gating) |
| `xcode26` (experimental, non-gating) | macos-26, Xcode 26.6, iOS 26.5 sim | ✅ (after fix) | ✅ 4/4 | ❌ 0/4 |

**Xcode 26 fix:** one compile error, "unable to type-check this expression in reasonable time", in `GlassesRig.lumaFrame`'s BGRA→luma one-liner. It was split into typed sub-expressions. Errors were captured in [https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38116666640](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38116666640), and the fix built green in [https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38117301155](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38117301155).

**Control: Meta's CameraAccess sample on macos-26 / Xcode 26.6** ([https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38118355688](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38118355688)):
- `testRegisterAndPairShowsCameraScreen` ✅
- **`testStartSessionThenStreaming` ✅**: a mock device reaches a started session and streams on the CI Simulator.
- `testEndSession` ❌, on a late step ("return to session-ready after stopping the preview").

So DAT mock sessions **do work** on this runner. The blocker is something in **our app's setup**, not the Simulator/runner, and **not the Xcode version** (Xcode 26 changed nothing for our app).

**Attempts on macos-26 (all ❌ 0/4; the device is listed, `linkState` stays `disconnected`, `compatibility` stays `undefined`, `AutoDeviceSelector.activeDeviceStream()` stays nil):**
| Attempt | Run | Result |
|---|---|---|
| Built with Xcode 26.6 (same code that failed on 16.4) | [https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38117301155](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38117301155) | 0/4; probe: all variants `disconnected/undefined` |
| `AutoDeviceSelector` + wait for `activeDeviceStream()` (CameraAccess style), instead of `SpecificDeviceSelector` + linkState | [https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38118355688](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38118355688) | 0/4, `active=nil` |
| `initiallyRegistered: false` + `Wearables.shared.startRegistration()` (MDK fake handler), like CameraAccess's registerViaUI | [https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38119157425](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38119157425) | registration 0→3 (registered) ✅, link still disconnected, 0/4 |
| CI-only: removed `UISupportedExternalAccessoryProtocols` + `external-accessory` background mode (absent in both samples; DAT does read them) | [https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38119977792](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38119977792) | 0/4 (experiment reverted) |

**Remaining differences from CameraAccess (untried; the next step if M7 is resumed):**
1. ~~**Pairing path.**~~ (tried 01:50 PT, no change) CameraAccess pairs **from the XCUITest process via the test server** (`MockDeviceTestClient.pairDevice()` with `MWDAT_TEST_SERVER_PORT_FILE`). MDK is enabled and `startTestServer(portFilePath:)` is started in `App.init` when `--ui-testing` is set. We pair in-process with `MockDeviceKit.shared.pairGlasses` after a button tap. This is the most promising candidate: a third test path (~1 CI cycle).
2. Swift 6 language mode / deployment target 17.2 (ours: Swift 5 mode, 17.0); `audio` background mode.

**Decision:** the honest gate is GlanceCore + Simulator build + `FakeGlassesUITests` on Xcode 16.4, with the same suite passing on Xcode 26 as a non-gating leg. `MockLoopUITests` keep running on every push and become gating again as soon as they pass.

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
| 4c | Control on `macos-26` + newest Xcode 26: Meta CameraAccess mock-pair test **and** our MockLoopUITests | [38115170427](https://github.com/mmaziesf/rayban-vlm-poc/actions/runs/38115170427) | **Meta CameraAccess `testRegisterAndPairShowsCameraScreen` ✅ PASSED** on macos-26 / Xcode 26.6 / iOS 26.5 Simulator (mock pair → active device). `testLaunchWithoutDeviceShowsHomeScreen` ❌ cold-launch timeout (infra). **Our GlanceApp did not compile with Xcode 26** (4 errors; the CI step piped through `tail -5`, so the error text was not captured) → our MockLoopUITests did not run there |

**Conclusion (2026-10-10 23:15 PT):** the DAT mock link **does work on a GitHub Simulator with Xcode 26** (Meta's own test passes). So the blocker is most likely **our toolchain**: `app-simulator` builds with Xcode 16.4, and DAT 1.0.1 + its samples target Xcode 26.4+. It is **not** our pairing order, threading, model, or entitlements: all were ruled out above. Not yet proven, because our app has not compiled under Xcode 26.

**Parked next step (one CI cycle, not started):**
1. Print the Xcode 26 compile errors (drop the `tail -5`), most likely Swift 6.2 concurrency/isolation changes, and fix them.
2. Move `app-simulator` to `macos-26` + Xcode ≥ 26.4.
3. If `MockLoopUITests` then pass, make them gating again.

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
