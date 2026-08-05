#!/usr/bin/env python3
"""Rewire Tunarr movie channels to smart-collection random-slot schedules.

Keeps channel numbers/names/icons. Replaces manual lineups with schedules that
re-query smart collections when regenerated.
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
import uuid

API = "http://127.0.0.1:8000/api"
MAX_DAYS = 30
TZ_OFFSET_MIN = 240  # America/New_York EDT


def api(method: str, path: str, body=None):
    if body is None and method in ("DELETE", "POST", "PUT", "PATCH"):
        body = {}
    data = None if body is None else json.dumps(body).encode()
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        API + path, data=data, method=method, headers=headers
    )
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise SystemExit(
            f"{method} {path} → {e.code}: {e.read().decode()[:1500]}"
        ) from e


def map_channel(name: str) -> tuple[str, str, str]:
    """Return (smart_collection_name, order, direction)."""
    m = re.fullmatch(r"(\d{4})s (Shuffle|Fresh)", name)
    if m:
        decade, variant = m.group(1), m.group(2)
        if variant == "Shuffle":
            return f"{decade}s", "shuffle", "asc"
        return f"{decade}s", "chronological", "desc"

    if name.endswith(" Shuffle"):
        return name[: -len(" Shuffle")], "shuffle", "asc"
    if name.endswith(" Classics"):
        return name, "chronological", "asc"
    if name.endswith(" Fresh"):
        return name, "chronological", "desc"

    # Mixes and exact-name channels
    return name, "shuffle", "asc"


def build_schedule(sc_id: str, order: str, direction: str) -> dict:
    return {
        "type": "random",
        "flexPreference": "distribute",
        "maxDays": MAX_DAYS,
        "padMs": 1,
        "padStyle": "slot",
        "randomDistribution": "uniform",
        "lockWeights": False,
        "timeZoneOffset": TZ_OFFSET_MIN,
        "slots": [
            {
                "id": str(uuid.uuid4()),
                "type": "smart-collection",
                "smartCollectionId": sc_id,
                "order": order,
                "direction": direction,
                "cooldownMs": 0,
                "weight": 100,
                "durationSpec": {"type": "dynamic", "programCount": 1},
                "index": 0,
            }
        ],
    }


def migrate_one(channel: dict, sc: dict, order: str, direction: str) -> int:
    cid = channel["id"]
    schedule = build_schedule(sc["uuid"], order, direction)
    preview = api(
        "POST",
        f"/channels/{cid}/schedule-slots",
        {"schedule": schedule},
    )
    programs = preview.get("programs") or {}
    if isinstance(programs, dict):
        prog_ids = list(programs.keys())
    else:
        prog_ids = [p["id"] for p in programs if p.get("id")]

    api(
        "POST",
        f"/channels/{cid}/programming",
        {
            "type": "random",
            "schedule": schedule,
            "programs": prog_ids,
            "seed": preview.get("seed"),
            "discardCount": preview.get("discardCount"),
        },
    )
    return len(preview.get("lineup") or [])


def main() -> None:
    channels = sorted(api("GET", "/channels") or [], key=lambda c: c["number"])
    sc_by_name = {c["name"]: c for c in (api("GET", "/smart_collections") or [])}

    ok = fail = 0
    for ch in channels:
        sc_name, order, direction = map_channel(ch["name"])
        sc = sc_by_name.get(sc_name)
        if not sc:
            print(f"  SKIP  #{ch['number']:02d} {ch['name']} — no SC '{sc_name}'")
            fail += 1
            continue
        n = migrate_one(ch, sc, order, direction)
        print(
            f"  ok    #{ch['number']:02d} {ch['name']} → {sc_name} "
            f"[{order}/{direction}] lineup={n}"
        )
        ok += 1

    print(f"Done: {ok} migrated, {fail} skipped")


if __name__ == "__main__":
    main()
