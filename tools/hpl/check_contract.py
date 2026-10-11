#!/usr/bin/env python3
"""CI contract check for Glance → HP Lifestyle exports: HMAC (fixture pairing) + both JSON schemas, line by line.
Usage: check_contract.py FILE.hplevent   (needs `pip install jsonschema`)"""
import json, os, sys
import jsonschema
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import hpl_event_sign as h

event = json.load(open(os.path.join(here, "hpl.event.v1.schema.json")))
wrapper = json.load(open(os.path.join(here, "hpl.signed_event.v1.schema.json")))
bad = 0
for path in sys.argv[1:]:
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if not line.strip():
            continue
        try:
            w = json.loads(line)
            jsonschema.validate(w, wrapper)
            assert h.verify(w, h.FIXTURE_PAIRING_ID, h.FIXTURE_SECRET), "bad signature"
            body = json.loads(w["body"])
            jsonschema.validate(body, event)
            assert body["type"] == "meal.logged" and body["producer"]["name"] == "glance"
            assert set(body["payload"]) == {"items"}, "unexpected payload keys"
            print(f"ok  {path}:{n} {body['event_id']}")
        except Exception as e:  # noqa: BLE001
            bad += 1
            print(f"BAD {path}:{n} {e}")
sys.exit(1 if bad else 0)
