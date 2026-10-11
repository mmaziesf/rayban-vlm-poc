# M1c: real Gemma 4 E4B on the phone (prep done on the box, 2026-10-10)

**Status:** wiring, flag, scripts and the model download are ready. **No real inference has run yet.** It needs a device with a GPU (below).

## Model
| | |
|---|---|
| File | `gemma-4-E4B-it.litertlm` (LiteRT-LM bundle) |
| Source | https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm |
| Size / sha256 | 3,659,530,240 bytes · `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` (HF `x-linked-etag`) |
| License | **Apache-2.0** (https://ai.google.dev/edge/litert-lm/models/gemma-4; HF model card `license: apache-2.0`). The repo is **not gated**: an anonymous download returned 200 on 2026-10-10. **H7 (accept a Gemma license on HF) is therefore resolved: no human step.** If you redistribute the weights, ship the Apache-2.0 notice. |
| On the box | `~/models/gemma-4-E4B-it.litertlm`. Downloaded with `tools/m1c/fetch_model.sh`; **sha256 verified** 2026-10-10 |
| Fallback | `VARIANT=E2B tools/m1c/fetch_model.sh` (2.58 GB) for lower-RAM phones, and for iOS (E4B vision is broken on LiteRT-LM iOS, #2370) |

## Where the model lives on the device
The app checks these locations in order (`VlmFactory.candidates`):
1. `/sdcard/Android/data/dev.arash.glance/files/models/gemma-4-E4B-it.litertlm` (`getExternalFilesDir("models")`).
   - This is the **adb push target**: no storage permission needed, and it is removed on uninstall.
2. `/data/data/dev.arash.glance/files/models/gemma-4-E4B-it.litertlm` (internal storage).
   - Fallback for debug builds: `run-as` copy, see `tools/m1c/push_model.sh`.

The app checks the **exact size** and refuses a partial push. It never downloads the model itself: the app is offline by design.

## Stub vs real switch
| How | Effect |
|---|---|
| default build | `BuildConfig.VLM_MODE="stub"` → `CannedVlmEngine`. Emulator, CI and `MockLoopTest` stay deterministic and green |
| `./gradlew :app:assembleDebug -Pglance.vlm=real` | `VLM_MODE="real"` → `LiteRtVlmEngine` if the model is present and RAM is enough |
| `adb shell am start -n dev.arash.glance/glance.app.MainActivity --es vlm real\|stub` | **Debug builds only**: runtime override of the build default |
| `adb shell "am broadcast … DebugCommandReceiver --es info vlm"` | logs the current selection |

The decision logic (`glance.core.VlmSelection`) is a pure function with 8 JVM tests:
- A **real** request falls back to **stub with a logged reason** when the file is missing, the push is partial, there is less than 3 GB of available RAM, or the engine fails to initialise (e.g. no GPU delegate).
- It never fails silently. Logcat shows: `GlanceVlm: mode=STUB reason="…"`.

## Offline constraints
- **Release APK:** `aapt dump permissions` → BLUETOOTH, BLUETOOTH_CONNECT, CAMERA and **no INTERNET** (re-checked 2026-10-10). That is the M1c offline proof.
- **Debug APK:** has INTERNET for the MDK preview/test server only. Real-mode timings from a debug APK are still on-device, because LiteRT-LM reads a local file.
- **No network toggle:** the bot can't put the phone in airplane mode without cutting its own adb-over-Wi-Fi link. Use USB adb, or rely on the release-APK permission proof.

## Where real inference can run
| Target | Real E4B? | Why |
|---|---|---|
| TCG emulator (this box) | **No** | No GPU delegate, 1.5 GB guest RAM, software CPU. The factory falls back to stub with a reason |
| **D1: the user's phone** (USB or Wi-Fi adb) | **Yes** | Target device. Needs ≥ 8 GB RAM and a recent Adreno/Mali GPU |
| Genymotion SaaS / cloud *virtual* devices | Unlikely | x86 virtual GPU; no LiteRT GPU delegate expected (VERIFY) |
| Cloud *physical* devices with adb (e.g. Firebase Test Lab physical, BrowserStack/Samsung Remote Test Lab) | Probably | Real phone GPUs. Needs an account, plus pushing a 3.66 GB file to a leased device, which may hit upload limits (VERIFY) |

## Bot runbook (once a device is attached)
    tools/m1c/fetch_model.sh          # done on the box (sha256 OK)
    tools/m1c/run_real.sh             # build -Pglance.vlm=real → install → push model → launch --es vlm real → N turns
                                      # → tools/m1c/parse_timings.sh: load_ms, infer p50/p90/max, M1C=PASS if p50 < 5 s

The logged timing lines are `GlanceVlm: load_ms=…` and `GlanceVlm: infer_ms=… jpeg_ms=… img=WxH`.
- LiteRT-LM's Kotlin API doesn't expose a prefill/decode split or the visual-token budget (VERIFY on newer releases), so M1c measures wall time.
