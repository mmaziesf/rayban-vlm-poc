# Glance → HP Lifestyle meal bridge (Android, primary)

Glance can send the meals it logged ("Hey Meta, log this meal") to **HP Lifestyle** (HPL), the iOS lifestyle app in
[heartypatch-lifestyle-ios](https://github.com/mmaziesf/heartypatch-lifestyle-ios). Contract: HPL `docs/m5-glasses.md`
(§1 mapping, §2 wire format, §3 pairing, §6 producer work). This repo implements §6 on Android.

**Offline by design.** No new permissions. The release APK still has no `INTERNET` (CI guard in `android.yml`).
Files leave the phone only through the Android share sheet, by your choice (Drive, Files, Signal, email, USB…).

## Flow
1. **Pair** (once). In HPL: Settings › Glasses meals › Pair a companion. It shows a QR + `hplpair://v1?id=…&k=…` link.
   On the Android phone either
   - scan the QR with any QR reader that can open the link → Android routes `hplpair://v1` to Glance's *HP Lifestyle* screen, or
   - copy the link → Glance › **HP Lifestyle: pair / send meals** → paste (or leave empty to use the clipboard) → *Pair*.

   Glance always asks before pairing and shows a code = first 8 hex of SHA-256(secret)
   (same as `hpl_event_sign.py pair` → `secret_sha256[:8]`). The 32-byte secret is AES-GCM-wrapped by a non-exportable
   Android Keystore key; only ciphertext is in private prefs (`allowBackup=false`). *Unpair* deletes both.
2. **Log meals** as before. Meals now persist (`files/meals/meals.tsv`, `FileMealStore`) instead of the in-memory placeholder.
3. **Review + send.** The HP Lifestyle screen lists meals newest first. Unsent meals are ticked by default; "sent" ones are
   unticked (tick to re-send); *Not a meal* hides a row for good. *Send ticked meals* writes
   `cache/hplevent/glance-<date>.hplevent` and opens the share sheet (`application/x-hplevent`, read grant via FileProvider).
   Rows are marked *sent* when handed to the share sheet. Re-sending is harmless: event ids are deterministic and HPL dedupes.
4. In HPL: open the file ("Open in HP Lifestyle") or Meals › Import. Meals arrive **pending**; you confirm them there.

## What is sent
One `hpl.signed_event.v1` line per meal; body = `hpl.event.v1` `meal.logged`:
`occurred_at` (UTC s), `tz` (device IANA zone, `UTC` if it isn't schema-valid), `producer {glance, versionName, on_device}`,
`items[0] {name ≤80, kcal_est?, protein_g?}`. `event_id` = ULID(tsMs, SHA-256("glance|tsMs|row<id>-t<frameTimeMs>|name")[:10]).
**Never sent:** frames, photos, raw VLM JSON. Files are chunked at ≤1,000 lines / ≤1 MB.

## Code
| File | What |
|---|---|
| `phone/core/.../HplBridge.kt` | `HplPairing.parse`, `Hpl.mealLoggedBody`, `signedLine`, `exportFiles`, `FileMealStore` (pure JVM) |
| `phone/core/.../HplTests.kt` | 23 checks: body + signature **byte-identical to the Python reference** (HPL fixture 07 / signed 01), escaping, chunking, store reopen |
| `phone/app/.../hpl/HplActivity.kt` | pairing + review + share screen; `hplpair://v1` VIEW intent filter |
| `phone/app/.../hpl/PairingStore.kt` | Keystore-wrapped secret |
| `phone/app/src/androidTest/.../HplBridgeTest.kt` | Keystore round trip, FileProvider export (fixture pairing; restores your pairing, discards its meal) |
| `tools/hpl/` | vendored `hpl_event_sign.py`, schemas, `check_contract.py` (CI: HMAC + schemas on a Kotlin-produced file) |

## Verified (2026-10-11, box TCG emulator, API 29)
- `HplBridgeTest` 2/2. UI: `adb shell am start -a android.intent.action.VIEW -d 'hplpair://v1?…'` → confirm dialog → Paired (code `ae216c2e` for the fixture) →
  Send → share sheet → file pulled with `run-as` passes `check_contract.py` (HMAC + both schemas).
- Release APK permissions: `BLUETOOTH_CONNECT`, `CAMERA`, `BLUETOOTH` only.

## Gaps
- Not yet imported by a real HPL build on an iPhone (needs device; HPL's Swift verifier is already cross-tested against the same Python reference).
- No in-app QR scanner (would need CameraX + a barcode lib). Whether a given phone's QR reader opens a custom `hplpair://` scheme varies; paste always works.
- HPL doesn't display the pairing code yet, so the code check is one-sided until HPL shows SHA-256(secret)[:8].
- "Sent" means handed to the share sheet, not delivered. Re-send is safe.
- iOS Glance port: not done (core logic is small; port `HplBridge.kt` to `GlanceCore` when the iOS app needs it).
- Room (Glance M4) can replace `FileMealStore` later; keep the row id in the event-id seed or store the ULID in the row.
