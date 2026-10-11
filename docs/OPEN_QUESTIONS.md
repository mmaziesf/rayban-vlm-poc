# Open questions / blockers (need real SDK, hardware, or measurement)

1. **Mock Device Kit + Display:** the FAQ says MDK doesn't support display glasses; the display-simulation page shows a `META_RAYBAN_DISPLAY` mock. Verify with the actual SDK version.
2. **Mock camera:** can MDK inject a still image or video for `Photo.capturePhoto` / stream? If not, M1 uses a bundled JPEG.
3. **Transport:** the iOS guide says Wi-Fi carries camera streaming; the Android guide says Bluetooth Classic. Real 720p JPEG transfer time is unknown.
4. **Dev/beta-only APIs:** `Photo`, `Speech` and voice invocations are marked "Dev and beta only". That's fine for a POC, but it blocks a production release until they go GA.
5. **Speech offline?** Confirm glasses ASR works in airplane mode on the phone.
6. **Display + speech + camera concurrency** in one `DeviceSession`: any documented limits? Audio route (A2DP) while `Speech` is active?
7. **Gemma 4 E4B image latency:** the published benchmarks are text-only. Measure vision encode at 70/140/280 token budgets on the target phone.
8. **Target phone:** which Android device does Arash have? E4B GPU needs a recent flagship (≥8 GB, ideally 12 GB RAM). Otherwise drop to E2B.
9. **Model delivery offline:** the 3.65 GB `.litertlm` is pushed via adb or downloaded once, then fully offline. Check the license acceptance flow on Hugging Face.
10. **Wearables MCP `search_webapps_docs`:** not queried in this pass. Use it next pass to double-check Web App QA details.
11. **Developer Mode** must be enabled in the Meta AI app; firmware ≥ V128 / Meta AI app ≥ V290 for DAT 1.0 (https://wearables.developer.meta.com/docs/develop/dat/version-dependencies).

## Streaming / rolling buffer (added for M2)

12. **4 fps is not possible.** DAT accepts only 2/7/15/24/30 fps. Decide between 2 fps (default) and 7 fps decimated after measuring answer quality and battery.
13. **Ladder below 15 fps:** does the bandwidth ladder drop resolution at 2 fps? Does it ever change fps there? Not documented.
14. **YUV layout** of `VideoFrame.buffer` (I420 vs NV12/NV21) and row stride/padding: not documented. `YuvJpeg.i420ToJpeg` assumes I420. Check by logging `buffer.remaining()` vs w×h×1.5 and saving one frame.
15. **Clock base** of `presentationTimeUs`: needed to compute true frame age (glasses capture → phone). Until then frame age = phone receipt time.
16. **Stream start latency** (start() → first frame). Decides whether "arm on first partial transcript" can replace always-on.
17. **Battery/thermal at 2 fps** on Ray-Ban Display over 30–60 min; does the display + speech + camera combination trigger `THERMAL_HOT` or `PEAK_POWER_LIMIT`?
18. **Concurrency:** `Stream.capturePhoto` while streaming is documented. Can the separate `Photo` capability run while the stream is active? (One camera per session.)
19. **PhotoData / TranscriptionResult field names on Android:** not confirmed from reference pages. Marked VERIFY in code.
20. **MockSpeechKit accessor** on `MockGlassesServices` (assumed `services.speech`) and whether `setCameraFeed` accepts an `android_asset` URI. Marked VERIFY.
21. **Display wake/sleep:** the display dims at 20 s and sleeps at 25 s; Back ends the display session. Should a voice answer wake the display? (Not documented.)
22. **Privacy:** an always-on camera keeps the glasses capture LED behavior (unknown for DAT streams) and stores ~3 s of frames in phone RAM only. Never write the buffer to disk except an explicitly logged meal frame.

## Autonomy / remote debugging (added 2026-10-10)

23. **Unattended real-glasses sessions:** do DAT camera, display and speech work while the glasses are DOFFED (not worn) but powered with the hinge open? If not, M3 needs a person wearing them.
24. **Does Mock Device Kit need Meta AI app registration** or Developer Mode on the phone? **Mostly resolved (javap):** `MockDeviceKitConfig(initiallyRegistered, initialPermissionsGranted)` lets the mock start registered and granted, and `MockRig` uses `(true, true)`. VERIFY on first run that no Meta AI app is needed at all.
25. **Wireless-debugging TLS port after reboot:** can the bot rediscover it without the user (no mDNS over the tailnet)? Otherwise each reboot costs one user message (H8). Option: Android "trusted network" auto-re-enable (Med source).
26. **Tailscale on the box:** kernel mode should work (`/dev/net/tun` rw + sudo) but is untested. The box is shared by all of Arash's agents, so any agent could use the adb key: decide whether that's acceptable or isolate it (separate Unix user for adb).
27. **Model transfer:** pushing 3.65 GB over the tailnet may go via a DERP relay (slow). Alternative: the bot gives Arash a one-time on-phone download step, or the app downloads the model itself on Wi-Fi, once, then works offline.
28. **Emulator on box:** `/dev/kvm` exists but the box user lacks access; free RAM is ~3–4 GB. Decide whether an emulator is worth it versus going straight to the physical phone (T1).
29. **Arash's phone model/Android version:** Android 11+ needed for Wireless debugging; 12 GB RAM preferred for E4B.

## Resolved by D0 compile (DAT 1.0.1 AARs inspected with javap, 2026-10-10)
- **#19 resolved:**
  - `TranscriptionResult(text, isFinal, confidence)`.
  - `Stream.capturePhoto()` is `suspend` → `DatResult<PhotoData, CaptureError>`.
  - `PhotoData` is `Bitmap(bitmap)` or `HEIC(data: ByteBuffer)`.
- **#20 partly resolved:**
  - `MockGlassesServices.speech` exists (also `camera`, `display`, `voiceInvocation`, `input`, `captouch`, `motion`, `cameraCapture`).
  - Sidestepped: we copy the asset to `cacheDir` and pass a `file://` Uri. Whether `file://` works is still VERIFY on first run.
- **Doc vs SDK mismatch:** the Display guide shows `flexBox(paddingAll = …)`, but SDK 1.0.1 names the parameter `padding`. `Display.sendContent` is `suspend`.
- `addDisplay` / `addCamera` / `addSpeech` are **extension functions**. They need the imports `com.meta.wearable.dat.display.addDisplay`, `...camera.addCamera` and `...speech.addSpeech`.
- `Device.isDisplayCapable()` is a member of `Device`.
- **Toolchain constraint:** LiteRT-LM 0.18.0 depends on kotlin-reflect 2.4.0, so the project uses Kotlin 2.4.21 + AGP 8.13.2 + Gradle 8.14.3. AGP 9.x is out but is not used yet: it changes Kotlin plugin handling.

- **Emulator on the bot box (2026-10-10): KVM no, TCG yes.** KVM vCPU creation oopses the box kernel; never use it. A software emulator (`tools/emu/tcg.sh`, API 29 x86_64, `-accel off`) runs the full mock loop: `MockLoopTest` 4/4, smoke PASS. See `EMULATOR_ALTERNATIVES.md`.
- **Resolved on emulator (2026-10-10):**
  - MDK runs with no Meta AI app or registration (`MockDeviceKitConfig(true,true)`).
  - `setCameraFeed(file://cache/...)` works with our H.265 504×896 clip (decoded by `OMX.google.hevc.decoder`).
  - Mock speech session listens once `addSpeech` starts.
  - The DAT stream delivers YUV frames into the ring buffer.
- **New:**
  - The MDK test server needs INTERNET and still didn't bind on the emulator. Why?
  - DAT 1.0.1 has manifest opt-outs `com.meta.wearable.mwdat.ANALYTICS_OPT_OUT` / `CRASH_REPORTING_OPT_OUT` (we set both true). Does anything else phone home on real glasses?

- **iOS (M7):** Can the bot get a GitHub repo for `rayban-vlm-poc`? A public one gets free macOS minutes; a private one bills macOS minutes. Access would be via the connected GitHub integration (currently `needsAuth`) or a repo-scoped PAT. This is the only blocker for running the iOS Simulator + MockDeviceKit tests (`docs/IOS_OPTIONS.md`).
