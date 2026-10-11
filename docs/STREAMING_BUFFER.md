# Low-FPS streaming + phone-side rolling buffer

Researched 2026-10-10 (PT). **High** = official doc/reference page read; **Med** = official snippet or GitHub; **Est** = my estimate, needs measurement.

## Recommendation (short)

**Preferred path for vision intents (M2/M3):**
- Keep a DAT camera stream open at **2 fps, MEDIUM (504×896)**, decoded YUV.
- Hold the last **6 frames (~3 s)** in a phone-side ring buffer.
- Answer "what am I seeing?" from the frame **pinned at the first partial transcript**, otherwise the freshest frame ≤1.5 s old.

**Keep Photo as the fallback:**
- Use `Stream.capturePhoto` / `Photo.capturePhoto` when the buffer is empty or stale.
- Also use it optionally for "log this meal", where quality matters more than speed.

**4 fps isn't available:**
- DAT accepts only **2, 7, 15, 24, 30** fps.
- If 2 fps is too coarse, use 7 fps and keep every second frame (~3.5 fps effective), at the cost of more link and battery load.

## 1. What DAT supports (facts)

| Item | Finding | Conf. | Source |
|---|---|---|---|
| Frame rates | `frameRate` accepted values: **2, 7, 15, 24, 30**. Android default 24, iOS `init()` default 30. | High | [Android StreamConfiguration](https://wearables.developer.meta.com/docs/reference/android/dat/latest/com_meta_wearable_dat_camera_types_streamconfiguration), [iOS StreamConfiguration](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest/mwdatcamera_streamconfiguration) |
| Resolutions | HIGH 720×1280, MEDIUM 504×896 (default), LOW 360×640 (portrait) | High | [Android integration](https://wearables.developer.meta.com/docs/develop/dat/build-integration-android/) |
| Compression | Link carries HEVC. `compressVideo=false` (default): SDK decodes on the phone and delivers **YUV**. `true`: raw HEVC buffers (+ VPS/SPS/PPS config frames) for your own decoder. | High | StreamConfiguration + [VideoFrame](https://wearables.developer.meta.com/docs/reference/android/dat/0.9/com_meta_wearable_dat_camera_types_videoframe) |
| Frame object | `VideoFrame(buffer: ByteBuffer, width, height, presentationTimeUs, isCompressed, isCodecConfig)`. **YUV plane layout not documented.** | High / layout unknown | VideoFrame ref |
| Backpressure | `videoStream` Flow "drops the oldest frames" on overflow | High | [Stream](https://wearables.developer.meta.com/docs/reference/android/dat/0.9/com_meta_wearable_dat_camera_stream) |
| Adaptive ladder | Under bandwidth pressure: lower resolution first, then fps, "never below 15 fps". Per-frame compression adapts. Lower res/fps can give *higher* visual quality. | High | Android integration |
| Ladder at 2 fps | **Unknown.** Docs don't say whether the ladder touches a stream requested below 15 fps. Likely only the resolution step applies. | Est | — |
| Still during stream | `Stream.capturePhoto` while streaming. Separate `Photo` capability (480p–4032×3024, dev/beta only). | High | Integration guide, [Photo](https://wearables.developer.meta.com/docs/reference/android/dat/1.0/com_meta_wearable_dat_camera_photo_photo) |
| One camera per session | `addCamera` again → `CAPABILITY_ALREADY_ADDED` | High | [DeviceSession](https://wearables.developer.meta.com/docs/reference/android/dat/0.9/com_meta_wearable_dat_core_session_devicesession) |
| Stream health | `StreamError`: `THERMAL_HOT`, `THERMAL_EMERGENCY`, `BATTERY_LOW`, `PEAK_POWER_LIMIT`, `HINGE_CLOSED`, `TIMEOUT`. `DeviceState` gives battery, don/doff, hinge, 8-level `ThermalLevel`. | High | [StreamError](https://wearables.developer.meta.com/docs/reference/android/dat/0.8/com_meta_wearable_dat_camera_types_streamerror), [Device state](https://wearables.developer.meta.com/docs/develop/dat/device-state/) |
| Mock feed | Mock Device Kit `setCameraFeed(Uri)` takes an **H.265** video (Android doesn't transcode) or the phone camera. Streams through the same API. | High | [MockCameraKit](https://wearables.developer.meta.com/docs/reference/android/dat/1.0/com_meta_wearable_dat_mockdevice_api_camera_mockcamerakit), [MDK](https://wearables.developer.meta.com/docs/develop/dat/mock-device-kit/) |
| Transport | iOS guide: Wi-Fi for camera streaming. Android guide: Bluetooth Classic. | Conflict | Integration guides |

**Is 2 fps a supported, stable mode?**
- **Supported: yes.** It's an accepted value.
- **Stable: unknown.** No doc covers long-running low-fps sessions, battery drain or thermal behavior. That's the first thing to measure on hardware (M3).

## 2. Phone-side rolling buffer feasibility

- **Store decoded YUV, not JPEG.**
  - YUV costs nothing per frame (the SDK already decoded it).
  - The luma plane gives a free sharpness score.
  - Convert only the **selected** frame to JPEG for the VLM (`Content.ImageBytes`).
  - Per-frame JPEG encoding would waste CPU on frames nobody asks about.
- **Memory (YUV420 = w×h×1.5):**

  | Quality | Per frame | 6 frames (3 s @ 2 fps) | 14 frames (2 s @ 7 fps) |
  |---|---|---|---|
  | LOW 360×640 | 0.35 MB | 2.1 MB | 4.8 MB |
  | MEDIUM 504×896 | 0.68 MB | 4.1 MB | 9.5 MB |
  | HIGH 720×1280 | 1.38 MB | 8.3 MB | 19.4 MB |

  Negligible next to the ~0.7–3.3 GB the VLM uses. A JPEG ring (≈50–150 KB/frame, **Est**) only matters if we keep minutes of history.
- **Why HEVC-in-buffer is rejected:**
  - Compressed buffers are tiny, but decoding one frame needs every frame since the last keyframe.
  - That's complex and adds latency at question time. Not worth it at 2 fps.
- **CPU, power and thermal:**
  - Phone side: decoding 2 fps HEVC plus a subsampled Laplacian (~1/64 of pixels) per frame is trivial (**Est**).
  - The real cost is the **glasses**: camera sensor, ISP and encoder stay on, plus the radio link.
  - Mitigations:
    - Stream only while the session is active and `donState == DONNED`.
    - Stop on `HINGE_CLOSED`.
    - Pause on `ThermalLevel` SEVERE or higher.
    - Honor `THERMAL_HOT`, `BATTERY_LOW` and `PEAK_POWER_LIMIT`.
    - Idle timeout (e.g. 120 s without a command), then fall back to **arm-on-partial**: restart the stream when the first partial transcript arrives.
  - Battery cost per hour at 2 fps is **unknown**. Measure it with `DeviceState.batteryLevel`.
- **Frame selection:**
  - The first partial transcript that looks like a vision request ("what…", "log…", "describe…") **pins** the newest frame. That's what the wearer was looking at when they started speaking.
  - On the final transcript, use the pinned frame if it's ≤3 s old. Otherwise pick the sharpest of the newest 3 frames ≤1.5 s old. Otherwise use the capture fallback.
  - Implemented and unit-tested in `phone/core` (`FrameRingBuffer.select`, `pinLatest`, `BufferedFrameSource`).

## 3. Latency vs on-demand Photo (M3)

| Step | Buffer (2 fps) | On-demand Photo |
|---|---|---|
| Wait for a frame | 0 ms (already on phone). Frame age ≤500 ms + pipeline (**Est** 100–300 ms) | Photo start (if stopped) + sensor capture + JPEG encode + transfer: **unknown**, guess 0.8–3 s for 720p (**Est**) |
| Frame → VLM input | YUV→JPEG ~10–30 ms (**Est**) | already JPEG |
| VLM (E4B GPU) | ~2.5–3.5 s to full answer (**Est**, from published text benchmarks) | same |
| **Perceived** | ≈ VLM time only | VLM + capture/transfer |
| Image quality | 504×896, HEVC-compressed video frame, possible motion blur (mitigated by sharpness pick) | 720p+ JPEG still, better detail |
| Glasses battery | continuous camera + link | camera only on request |
| Best for | "what am I seeing?" (latency-critical) | "log this meal" (detail matters; latency less so), fallback |

**Hybrid:**
- Describe → buffer.
- Log meal → buffer frame for the instant HUD acknowledgement, plus an optional `Stream.capturePhoto` for the stored record and a refined estimate.
- Chat about the last scene → reuse the last pinned frame.

## 4. Measurement plan (M3, hardware)

1. Stream `start()` → first frame latency, at 2 and 7 fps (needed to judge arm-on-partial).
2. Frame age at receipt: compare `presentationTimeUs` with the phone clock. VERIFY that the time bases are comparable.
3. Delivered resolution and fps over 10 min (does the ladder kick in at 2 fps?).
4. Glasses battery %/10 min and `ThermalLevel` at 2 fps vs idle.
5. `Stream.capturePhoto` and `Photo.capturePhoto(MEDIUM)` round-trip latency (p50/p95).
6. VLM answer quality: buffered MEDIUM frame vs 720p still, on 20 scenes.
