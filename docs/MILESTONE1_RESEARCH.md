# Milestone 1 Research — On-device VLM with Meta Ray-Ban Display + phone

Researched 2026-10-10 (PT). Sources are linked inline. Confidence: **High** = read on an official doc page; **Med** = official search snippet or GitHub issue; **Low/Est** = my estimate or inference, not documented.

---

## TL;DR

| Topic | Finding | Conf. |
|---|---|---|
| Single-frame capture | Yes. Two documented paths: `Stream.capturePhoto` during an active stream, and a separate `Photo` capability with `capturePhoto(resolution, quality)` (dev/beta channel only). | High |
| Frame size | Stream: 720×1280 / 504×896 / 360×640 at 2/7/15/24/30 fps. Photo: small 480p, medium 720p (default), large 1080p, full 4032×3024. JPEG for stills. | High |
| Continuous 720p | Possible on paper, but the link adapts: it drops resolution first, then fps (never below 15). Frames are recompressed per frame. **Don't build on continuous 720p.** **Update (M2):** a low-fps stream (2 fps MEDIUM) + phone ring buffer is now the preferred source; Photo is the fallback. See `STREAMING_BUFFER.md`. | High |
| Glasses display | DAT Display capability: the phone sends FlexBox/Text/Image/Button/Icon/Video layouts; taps/focus come back as events. Ray-Ban Display only. | High |
| Audio out (TTS) | Phone TTS goes to the glasses over A2DP (44.1/48 kHz). HFP (mic) is 8 kHz mono and pushes output down to 8 kHz while it's active. | High |
| Voice in | `Speech` capability: speech recognition runs on the glasses and only text reaches the phone (partial/final). "Hey Meta, start {app}" launches the app through Voice Invocations. Dev/beta only. | High |
| Web Apps path | Plain HTML/CSS/JS on the glasses, 600×600. **No camera, no mic.** It does have `speechSynthesis`, `localStorage` (5 MB) and Service Worker offline. | High |
| Simulator | Chrome extension. It previews Web Apps **and** DAT Display content from a Mock Device Kit test server (`127.0.0.1:9000`). | High |
| Gemma 4 E4B | Real model. Inputs: text, image and audio. LiteRT-LM `.litertlm` is 3.65 GB. GGUF + mmproj exist for llama.cpp. | High |
| E4B on phone | S26 Ultra GPU: TTFT 0.8 s, 22 tok/s decode, 710 MB peak CPU memory. CPU: TTFT 5.3 s, 3.3 GB. | High (bench conditions: 1024 prefill/256 decode, text) |
| Platform pick | **Android** (see §6). | — |

---

## 1. Camera: on-demand frames over the glasses link

- **Stream config** (Android and iOS integration guides):
  - `StreamConfiguration` takes `frameRate` ∈ {2, 7, 15, 24, 30}.
  - Resolution options: HIGH 720×1280, MEDIUM 504×896, LOW 360×640.
  - The automatic bandwidth ladder lowers resolution first, then fps (never below 15).
  - Per-frame compression adapts to Bluetooth Classic bandwidth. Per the docs, requesting a lower resolution or fps "can yield higher visual quality with less compression loss".
  - Sources: https://wearables.developer.meta.com/docs/develop/dat/build-integration-android/ and https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/
- **In-stream still:** call `capturePhoto` while a stream session is active, and handle `PhotoData`.
- **Standalone `Photo` capability** (DAT 1.0, *dev/beta only, not for production release channels*):
  - `capturePhoto(resolution, quality)` delivers results asynchronously on `photoStream` (Android) or `photoDataPublisher` (iOS).
  - Default is medium (720p) resolution at medium quality. Higher settings add processing time, file size and battery drain.
  - Sources: https://wearables.developer.meta.com/docs/reference/android/dat/1.0/com_meta_wearable_dat_camera_photo_photo, https://wearables.developer.meta.com/docs/reference/ios_swift/dat/1.0/mwdatcamera_photo, https://wearables.developer.meta.com/docs/reference/ios_swift/dat/1.0/mwdatcamera_photoresolution
- **Transport inconsistency (open):**
  - The iOS guide says BLE handles discovery/control and **Wi-Fi** carries high-bandwidth camera streaming.
  - The Android guide says stream quality is limited by **Bluetooth Classic**.
  - Treat the transport as variable and measure it on hardware.
- **Recommendation for this POC:**
  - Use on-demand `Photo.capturePhoto(MEDIUM, MEDIUM)` → JPEG at about 720p → downscale on the phone to the VLM's input budget.
  - Gemma 4 uses 16×16 patches with a visual-token budget of 70/140/280/560/1120 (source: [LiteRT-LM Gemma4 config](https://github.com/google-ai-edge/LiteRT-LM/blob/fe0fcbdc/runtime/conversation/model_data_processor/gemma4_data_processor_config.h)). At a 280-token budget, a 720p frame is already more than the model will use, so 1080p/full only costs transfer time.
  - Fallback if `Photo` can't be used: start a LOW/MEDIUM stream at 2–7 fps, grab one frame (`capturePhoto` or the latest frame), then stop the stream.
  - Transfer latency for one 720p JPEG is **unknown**. Measure it in M3.

## 2. Display, audio, voice

- **Display (DAT `mwdat-display`):**
  - The phone builds component layouts (FlexBox, Text, Image, Button, Icon, Video). The SDK serializes them, sends them to the glasses, and routes interactions back to the app.
  - Add the capability only after `DeviceSessionState.STARTED`, and send content only after `DisplayState.STARTED`.
  - The DAT glasses app must be installed and up to date (`openDATGlassesAppUpdate`).
  - Sources: https://wearables.developer.meta.com/docs/develop/dat/display-overview/, https://raw.githubusercontent.com/facebook/meta-wearables-dat-android/main/plugins/mwdat-android/skills/display-access/SKILL.md, release note https://github.com/facebook/meta-wearables-dat-ios/discussions/178
- **Speaker:**
  - A2DP is output-only and high quality, and the docs list it for TTS. HFP is bidirectional at 8 kHz mono, and the two are mutually exclusive.
  - A camera stream can carry mic audio *without* switching to HFP, but that path is experimental and not publishable.
  - **POC choice:** generate TTS on the phone (Android `TextToSpeech`, offline voice) and play it over A2DP.
  - Source: https://wearables.developer.meta.com/docs/develop/dat/microphones-and-speakers/
- **Voice commands:**
  - `Speech` capability (`session.addSpeech()`): ASR runs on the glasses, and partial/final text arrives in the phone app. Dev/beta only.
  - Source: https://wearables.developer.meta.com/docs/reference/ios_swift/dat/1.0/mwdatspeech_speech
  - **Command parsing is our job.** Match the final transcript against intents ("what am I seeing/looking at" → DESCRIBE, "log this (meal)" → LOG). Free-form text → CHAT.
  - **Wake word:** there's no custom wake-word API. The documented system path is "Hey Meta, start {APP}" through Voice Invocations: the app is launched/foregrounded and must acknowledge each invocation. Source: https://wearables.developer.meta.com/docs/develop/dat/voice-invocations/
  - In-app, keep `Speech` running while the session is active (push-to-talk via a Display Button is the fallback).
  - Whether `Speech` needs a network connection is **unstated**. The docs only say it's "on-device". Verify it in airplane mode.

## 3. Simulator and Web Apps vs the DAT companion

- **Web Apps:**
  - Standalone HTML/CSS/JS on the glasses: 600×600, D-pad → arrow keys/Enter, `speechSynthesis` through the glasses speaker, `localStorage` 5 MB, Service Worker offline, PNG icons ≥52 px (no SVG).
  - **Camera and Microphone are "not yet supported"**, so a Web App can't be the eyes for this POC.
  - Source: https://wearables.developer.meta.com/docs/develop/webapps/build/
- **Meta Ray-Ban Display Simulator** ([Chrome Web Store](https://chromewebstore.google.com/detail/jpjlmmodokemlepklkdbimceggpbjcll)):
  - 600×600 additive frame, scenes/custom image/webcam backgrounds, D-pad + Select, brightness/blur, WebM recorder, "View on Glasses" QR.
  - **QA checklist:** viewport meta, favicon, D-pad focusables, horizontal overflow, visible focus.
  - Sources: https://wearables.developer.meta.com/docs/develop/webapps/test/, https://github.com/facebook/meta-wearables-webapp/blob/main/README.md
- **Key finding — the same extension previews DAT Display output:**
  - Mock Device Kit pairs a `GlassesModel.META_RAYBAN_DISPLAY` mock and runs `startTestServer(9000)`.
  - On Android: `adb forward tcp:9000 tcp:9000` → open `http://127.0.0.1:9000/` in Chrome → toggle the extension. This works with an emulator **or a USB-connected physical Android phone**.
  - On iOS it works **only from the iOS Simulator, not a physical iPhone**.
  - Source: https://wearables.developer.meta.com/docs/develop/dat/display-simulation
- **Doc conflict:** the FAQ (https://developers.meta.com/wearables/faq/) says Mock Device Kit "doesn't support display glasses", but the display-simulation page shows a Ray-Ban Display mock. The page is newer and more specific, so I trust it, but confirm it once the SDK is installed.
- **What this means for the plan:**
  - The `webapp/` scaffold is a fast **UX prototype** of the HUD states, validated in the extension's Web App mode.
  - The **real** glasses UI is the companion app's DAT Display layout, previewed through the same extension via Mock Device Kit.
  - Both get the same QA treatment. The extension's automated checklist is aimed at Web Apps; how much of it applies to DAT previews is unverified.
- **Wearables MCP:**
  - Endpoint https://mcp.developer.meta.com/wearables with the tool `search_webapps_docs` is documented on the build page.
  - I did **not** call it: a probe was interrupted, and this agent has no client configured for it. The findings above come from fetched docs pages.

## 4. Gemma 4 E4B on the phone

- **The model exists:**
  - `google/gemma-4-E4B-it`: 4.5 B effective params (8 B with Per-Layer Embeddings), text + image + audio in, 128 K context, native function calling.
  - Sources: https://huggingface.co/AtomicChat/gemma4-e4b-it-GGUF, https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
- **LiteRT-LM (recommended):**
  - The Google AI Edge on-device runtime; the docs say it powers AI Edge Gallery. I'm using only its public library, not forking Gallery.
  - `.litertlm` is 3.65 GB. Main weights stay resident, embeddings are memory-mapped, and vision/audio encoders load on demand.
  - Kotlin, Swift, C++ and Python APIs. Image input via `Content.ImageFile(path)`.
  - Sources: https://developers.google.com/edge/litert-lm/models/gemma-4, https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
  - About "MediaPipe": I believe the older MediaPipe LLM Inference API was superseded by LiteRT-LM for Gemma-class models. I didn't verify that on a fetched page (**Low**). Target LiteRT-LM either way.
- **Published E4B benchmarks** (1024 prefill / 256 decode, 2048 context; text-only, so no image-encoder time is included):

  | Device | Backend | Prefill tok/s | Decode tok/s | TTFT | Peak CPU mem |
  |---|---|---|---|---|---|
  | Galaxy S26 Ultra | CPU | 195 | 18 | 5.3 s | 3283 MB |
  | Galaxy S26 Ultra | GPU | 1293 | 22 | 0.8 s | 710 MB |
  | iPhone 17 Pro | CPU | 159 | 10 | 6.5 s | 961 MB |
  | iPhone 17 Pro | GPU | 1189 | 25 | 0.9 s | 3380 MB |

- **Known bug:** on Android, a CPU vision backend crashes (SIGSEGV) on the second image turn. Use `visionBackend = Backend.GPU()`. Also declare the vendor native libs in the manifest (`libOpenCL.so`, etc.), or it falls back to Dawn/Vulkan and can be OOM-killed. Source: https://github.com/google-ai-edge/LiteRT-LM/issues/2056
- **Latency estimate for one frame + short prompt** (**Est**, GPU, flagship):
  - Vision encode at a 280-token budget: unknown, guess 0.3–1 s.
  - Prefill of ~320 tokens: ~0.25 s.
  - Decode of a 40-token answer: ~1.8 s.
  - **≈2.5–3.5 s to the full answer**, plus capture/transfer (unknown) and TTS start.
  - Stream tokens and start TTS on the first sentence to cut perceived latency.
- **llama.cpp alternative:**
  - GGUF quants + `mmproj-gemma4-e4b-it-f16.gguf`, run through `llama-mtmd-cli` / `llama-server`.
  - Works, but the Android integration is DIY via JNI and GPU acceleration on mobile is less turnkey.
  - Keep it as a fallback or for desktop eval of prompts.
- **Device floor (Est):** 8 GB RAM minimum and 12 GB+ preferred (3.65 GB file + KV cache + app). Fallback model: **Gemma 4 E2B** (same family, smaller). Its exact numbers weren't fetched.

## 5. Local DB (later milestones)

- **Android:** Room on SQLite; `meals(id, ts, frame_path, label, kcal_est, protein_g_est, raw_json, model_ver)`.
- **iOS:** SwiftData or GRDB (SQLite).
- **Store:** the JPEG on disk with its path in the DB, plus the raw model JSON for re-parsing.
- **Structured extraction:** ask Gemma for JSON (function calling is supported per the model card) and validate it before insert.
- **No network dependency anywhere.**

## 6. Platform pick: **Android first**

Why Android:
1. **Simulator loop with a real phone:** the DAT Display preview in the Chrome extension works on a physical Android device via `adb forward`. On iOS it only works in the iOS Simulator, which can't run a 3.6 GB GPU VLM realistically. Android lets one device run the real model *and* preview the glasses UI in the extension.
2. **Runtime maturity for vision:** the LiteRT-LM Android Kotlin guide documents multimodal input with a GPU vision backend, and the known crash has a documented workaround. S26-class GPU numbers: TTFT 0.8 s at 710 MB.
3. **Dev ergonomics:** sideloading, `adb push` of the 3.65 GB model, and file access are simpler. There's no App Store/TestFlight step for a dev-channel DAT build.

iOS stays viable later: the DAT Swift API is equivalent and the iPhone 17 Pro GPU TTFT is 0.9 s. It's a port target for after the vertical slice works.

## 7. Recommended M1 architecture (simulator-first)

```
[Glasses / Mock Device Kit RBD]          [Android companion app]
  Speech (glasses ASR) ── text ──────▶  IntentRouter (describe | log | chat)
  Photo.capturePhoto(720p JPEG) ─────▶  FrameCache → resize to VLM budget
  Display ◀── layout (status/answer) ──  HudPresenter (same states as webapp/)
  A2DP speaker ◀── TTS audio ─────────  Android TextToSpeech (offline)
                                         VlmEngine: LiteRT-LM Gemma 4 E4B (GPU)
                                         MealLog: Room/SQLite
```

**M1 slice:**
- `webapp/` mock (done, passes local QA).
- Then an Android app that:
  1. Pairs the Mock Device Kit RBD.
  2. Shows the HUD via Display.
  3. Takes a **bundled test JPEG** as the "captured frame" (Mock Device Kit camera fidelity is unknown).
  4. Runs one E4B inference.
  5. Shows the answer on the Display preview and speaks it with phone TTS.
