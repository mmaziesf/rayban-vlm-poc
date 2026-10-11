# Glance VLM — HUD prototype (Milestone 1a)

A static 600×600 Web App that mocks the full M1 loop:

idle → listening → capturing → thinking → answer (spoken via `speechSynthesis`) → optional "Log this meal" → logged.

M2 adds a mock **live buffer** (2 fps):
- The chip in the top-right shows `Live 2 fps · <last frame age>`.
- Answers come from the buffered frame (meta line starts with `buffer · frame N ms`).
- "📷 Live cam off" makes the buffer go stale, which forces the slow `capture` fallback (~1.8 s mock).

- No hardware, no network, no build step.
- `MockBrain` in `app.js` stands in for the Android companion app (DAT capture + Gemma 4 E4B). Its `captureFrame()` / `infer()` shapes match the planned bridge.

Files: `index.html`, `styles.css`, `app.js`, `icon-96.png`.

## Run locally
```bash
cd webapp && python3 -m http.server 8765
# open http://127.0.0.1:8765/  (Chrome DevTools → device toolbar → 600×600)
```
Controls (same events the glasses send):
- Arrow keys = D-pad (move focus)
- Enter = Select/pinch
- Esc/Backspace = Back to idle

## Run in the Meta Ray-Ban Display Simulator
1. Install it: https://chromewebstore.google.com/detail/jpjlmmodokemlepklkdbimceggpbjcll and pin it.
2. Open `http://127.0.0.1:8765/` and click the extension icon to toggle the simulator.
3. **QA checklist** (must be all green):
   - viewport meta
   - favicon
   - D-pad focusable elements
   - no horizontal overflow
   - visible focus styles
4. **Performance scorecard:** record memory, startup time and download size. Local baseline from headless Chrome is below.
5. **Manual checks:**
   - D-pad through all 4 buttons; Select each one. Toggle Live cam off and confirm the slower fallback.
   - Run against built-in scenes (bright and dark), a custom background image, and the **webcam** feed.
   - Readability at low app brightness.
   - Back from the answer returns to idle.
   - Back at idle lets the system menu show.

## Automated local QA (approximation, not the extension)
```bash
cd tools && npm i && node qa.mjs http://127.0.0.1:8765/
```
This checks the same 5 checklist items plus:
- mrbd meta tag
- ≥88 px targets
- arrow reachability
- focus restore
- both mock loops
- no JS errors
- perf numbers

Last run (2026-10-10 PT, M2): **20/20 PASS** — DOMContentLoaded 120 ms, JS heap 1.63 MB, transfer ≈10.3 KB. New checks:
- buffer chip live
- answer uses buffered frame, under 1.5 s
- stale buffer falls back to capture
- focus stays on the trigger while busy

## Deploy notes (do NOT deploy as part of M1)
1. **Host on HTTPS** with a valid certificate at a public URL (e.g. GitHub Pages, Cloudflare Pages, Netlify, Vercel).
   - The app is fully static.
   - If you add a Service Worker for offline mode, HTTPS is required.
2. Open the exact URL in desktop Chrome and confirm there are no console/network errors. Re-run the simulator QA against the hosted URL.
3. Load it on the glasses, either way:
   - **Developer Mode in the Meta AI app:** enable Developer Mode, then add a Web App connection with the HTTPS URL. See https://wearables.developer.meta.com/docs/develop/webapps/ (Setup).
   - **"View on Glasses" QR** from the simulator extension: scan it with the phone paired to the glasses to deep-link-add the app.
4. Validate on the device: readability outdoors, D-pad/Neural Band input, Back behavior, TTS through the speakers.

**Reminder:** the Web Apps runtime has **no camera/mic access**. The real product HUD will be rendered by the Android companion app through the DAT Display capability. This prototype locks in states, copy and layout.
