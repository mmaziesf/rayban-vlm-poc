# Running Android end-to-end without Arash's phone

**Status (2026-10-10, 18:05 PT):** ✅ achieved **on the bot box** with a **software-only (TCG) emulator**.
- Debug APK + Meta DAT Mock Device Kit run end-to-end.
- `MockLoopTest` **OK (4 tests)**.
- `smoke.sh` **PASS** on both the broadcast path and the mock-speech path.
- No KVM, no human, box left healthy.

## Ranked candidates
Goal: run `connectedDebugAndroidTest` + `tools/adb/smoke.sh` (DAT Mock Device Kit + our debug APK) without the phone.

| # | Option | Works here? | Speed | Human/credentials needed | Verdict |
|---|---|---|---|---|---|
| **1** | **TCG emulator on the box** (`-accel off`, API 29 x86_64 AOSP, 1.5 GB) | ✅ **Tried, passes** | Boot 191 s; install 90 s; suite ≈100 s; one turn 4–17 s (each DAT display render takes 1.5–3 s) | none | **Use now** for M1b/M2/M2.5 and any non-GPU loop. `tools/emu/tcg.sh up/down` |
| 2 | **Genymotion SaaS** (cloud Android VMs with a real `adb` endpoint via `gmsaas instances adbconnect`) | not tried (needs account) | KVM-fast | Arash: account + API token (`gmsaas auth token …`); paid per minute | Best *cloud* fit: `smoke.sh` and `am instrument` run **unchanged** over adb |
| 3 | **Firebase Test Lab** (`gcloud firebase test android run --app … --test …`) | not tried (needs GCP project) | fast; virtual + physical | Arash: Firebase/GCP project + service-account key. Spark: 10 virtual runs/day free. Blaze: 60 virtual min/day free, then $1/device-h; physical $5/device-h | Good for instrumentation (our `MockLoopTest` as-is). **No interactive adb**, so `smoke.sh` doesn't apply. Physical Pixels could give real **GPU** numbers for M1c (model push via `--other-files`: VERIFY size limits) |
| 4 | **Kubernetes with KVM nodes** (GKE `--enable-nested-virtualization`, or bare-metal nodes) | manifests written + validated (`infra/k8s`), not deployed | KVM-fast, parallel, reproducible up/down | Arash: cloud project/billing + kube context + image registry | Best *long-term CI*. See `K8S_ANDROID_ENV.md` |
| 5 | Kubernetes, **TCG emulator pods** (any cluster, no privileges) | manifests written (`overlays/tcg`) | same as #1 | a cluster | Only useful if we already had a cluster. **No gain over #1 on this box** |
| 6 | AWS Device Farm / BrowserStack App Automate / Sauce Labs | not tried | fast, real devices | paid accounts + API keys | Fine for instrumentation runs. Heavier setup than #2/#3; no adb loop |
| 7 | **Phone over Tailscale (D1)** | waiting on H1–H4 | real | ≈10 min one-time | **Still needed** for real GPU inference (M1c) and real glasses (M3). Backup for everything else |
| ✗ | KVM-accelerated emulator on the box | ❌ **crashed host kernel** | — | — | `kernel BUG at arch/x86/kvm/x86.c:702` in `vmx_vcpu_create` (the box is itself a KVM guest; nested VMX broken). **Never retry** |
| ✗ | arm64 image under TCG | ❌ | — | — | Emulator panics for arm64 guests on x86_64 hosts at API ≥ 28. DAT needs **minSdk 29** |
| ✗ | redroid / Waydroid / Anbox on the box | ❌ | — | — | Need binder (`binder_linux`/binderfs). This kernel has no binder, `modules_disabled=1`, no `/lib/modules` |
| ✗ | Cuttlefish | ❌ | — | — | Requires KVM |
| ✗ | Remote desktop into a nested hypervisor | ❌ | — | — | Same nested-virt limit; nothing gained |
| ✗ | kind/k3s locally on the box | ❌ no gain | — | — | Same kernel: no KVM, no binder. No container runtime installed |
| partial | Robolectric (JVM) | not tried | fast | none | Can't load DAT's Android-native `.so` libs. Our pure-Kotlin core is already covered by 41 JVM tests |

## What was tried (exact)
1. **KVM AVD**: created a `kvm` group (gid 103), added `box`, then booted an API 35 AVD.
   - `-accel-check` said usable, but vCPU creation **oopsed the box kernel**.
   - The qemu process held a lock, and reading its `/proc/<pid>/cmdline` hung (killed by PID).
   - Reverted: group removed, AVD deleted.
2. **TCG AVD** (`tools/emu/tcg.sh`):
   - `system-images;android-29;default;x86_64`, `-accel off -gpu swiftshader -memory 1536 -cores 4 -no-window -no-snapshot`.
   - Watchdog: abort if MemAvailable < 1500 MB or boot > 420 s.
   - The script refuses to start if `/dev/kvm` is writable.
   - Booted in **191 s**. Host MemAvailable stayed ≥ 2.2 GB. No new kernel messages.

## Bugs the emulator found (all fixed)
| Bug | Fix |
|---|---|
| MDK `startTestServer` → `SocketException: EPERM` (the app has no INTERNET) → loop never started | INTERNET added to the **debug manifest only** (release still has none, checked with aapt). Test server made non-fatal |
| `adb shell am broadcast --es text "what am I seeing"` delivered `"what"` (adb re-splits through sh) → routed to text chat | `smoke.sh` and the docs now quote inside: `adb shell "am broadcast … --es text 'what am I seeing'"` |
| Negative frame age (`frame -401 ms old`): `t0` taken before a frame that arrived while `Capturing` rendered | Age now measured at selection time and clamped to ≥ 0. New JVM regression test (core 41/41) |
| DAT 1.0.1 queues **analytics + crash uploads** (`AnalyticsUploader` errors in logcat) | Main manifest sets `com.meta.wearable.mwdat.ANALYTICS_OPT_OUT=true` and `CRASH_REPORTING_OPT_OUT=true`. Re-run: 0 uploader lines |
| Test flakiness on slow devices: fixed 15 s timeouts; cumulative `totalPushed` made later tests skip the frame wait; TTS assert raced the display render | `-e timeoutScale N` instrumentation arg; baseline-relative frame wait; wait-for-speech |
| `smoke.sh` hung when the app was already running (no fresh "Loop running") | `smoke.sh` force-stops first; `SMOKE_SLOW` multiplier; honours `ANDROID_SERIAL` |

## Still open / limits of the TCG path
- **No GPU and too little RAM for real Gemma 4 E4B (M1c).** Real inference timings need the phone (D1), or FTL/Genymotion physical/GPU devices.
- MDK Chrome preview server still doesn't bind on the emulator, even with INTERNET (VERIFY on phone). The HUD is asserted via logcat instead.
- `simulateLaunchAppAction` ("Hey Meta, start Glance") not yet asserted in tests.
- TCG timings are ~5–10× a phone. Don't read latency numbers from it.

## Sources
- Emulator acceleration (no VM-accelerated emulator inside a VM; `-accel-check`): https://developer.android.com/studio/run/emulator-acceleration
- arm64-on-x86_64 panic for API ≥ 28: https://stackoverflow.com/questions/70251107 , https://github.com/ReactiveCircus/android-emulator-runner/issues/235
- TCG fallback behaviour: https://aospbooks.github.io/android-emulator-internal-book/05-cpu-acceleration/ ; non-KVM runners discussion: https://github.com/google/android-emulator-container-scripts/issues/21
- redroid kernel requirements: https://github.com/remote-android/redroid-doc/tree/master/deploy , https://github.com/remote-android/redroid-modules
- Firebase Test Lab CLI + pricing: https://firebase.google.com/docs/test-lab/android/command-line , https://firebase.google.com/docs/test-lab/usage-quotas-pricing
- Genymotion SaaS adb: https://docs.genymotion.com/tools/saas/gmsaas/ , https://docs.genymotion.com/usage/saas/connect_adb/
- AWS Device Farm instrumentation: https://docs.aws.amazon.com/devicefarm/latest/developerguide/test-types-android-instrumentation.html
- BrowserStack Espresso: https://www.browserstack.com/docs/app-automate/espresso/execute-tests

## One-time asks if we go cloud (pick one; none needed today)
- **Genymotion SaaS:** Arash creates an account and gives the bot an API token (store it in a box env file, never in the repo). The bot runs `pip install gmsaas`, `gmsaas auth token`, `gmsaas instances start <recipe>`, `adbconnect`, and then the normal scripts.
- **Firebase Test Lab:** Arash creates a Firebase project (Spark is enough to start) and a service account with the *Firebase Test Lab Admin* role, then shares the JSON key. The bot runs `gcloud auth activate-service-account` and `gcloud firebase test android run`.
