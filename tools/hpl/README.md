# tools/hpl — HP Lifestyle bridge contract (vendored)

Copied from [heartypatch-lifestyle-ios](https://github.com/mmaziesf/heartypatch-lifestyle-ios) @ `d91c027` (M5):

| File | Upstream |
|---|---|
| `hpl_event_sign.py` | `scripts/hpl_event_sign.py` (reference producer: pair / glance / sign / verify) |
| `hpl.event.v1.schema.json`, `hpl.signed_event.v1.schema.json` | `Spec/` |
| `01-glance-meal.synthetic.hplevent` | `Fixtures/signed/` (signed with the PUBLIC test-only pairing `fixturepair00001`) |

`check_contract.py FILE.hplevent` verifies HMAC (fixture pairing) + both schemas. CI (`android.yml`) runs it on a
file the Kotlin core produces (`HPL_CONTRACT_OUT=… ./gradlew :core:coreTests`). If the upstream spec changes, re-copy.
See `docs/HPL_BRIDGE.md`.
