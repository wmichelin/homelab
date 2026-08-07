#!/usr/bin/env python3
"""Create/update Tunarr #54 Sitcoms Shuffle (Seinfeld / Friends / The Office).

Equal-weight random slots (shuffle within each show). Leaves #53 Seinfeld 24/7 alone.

Run on G5:  python3 scripts/tunarr-seed-sitcoms-shuffle.py
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
import uuid

API = "http://127.0.0.1:8000/api"
TC = "595a6a45-be24-4ee5-8934-9f50a8f8100a"
CHANNEL_NUMBER = 54
CHANNEL_NAME = "Sitcoms Shuffle"
GROUP = "TV"
TZ_OFFSET_MIN = 240  # America/New_York EDT
MAX_DAYS = 30

# Tunarr program_grouping UUIDs (title as stored in Tunarr DB).
SHOWS = [
    ("Seinfeld", "b4719127-a7c5-4ecd-a04a-b144c0428b5e"),
    ("Friends", "1213df50-5562-44b4-a194-8c5c1778ff76"),
    ("The Office", "ed7467e1-a5ce-4c22-96aa-b3592c15ab3b"),
]


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
        detail = e.read().decode(errors="replace")[:2000]
        raise SystemExit(f"{method} {path} → {e.code}: {detail}") from e


def find_channel() -> dict | None:
    for ch in api("GET", "/channels") or []:
        if ch.get("number") == CHANNEL_NUMBER or ch.get("name") == CHANNEL_NAME:
            return ch
    return None


def channel_body(existing_id: str | None = None) -> dict:
    now = int(time.time() * 1000)
    return {
        "id": existing_id or str(uuid.uuid4()),
        "name": CHANNEL_NAME,
        "number": CHANNEL_NUMBER,
        "groupTitle": GROUP,
        "duration": 0,
        "disableFillerOverlay": False,
        "fillerRepeatCooldown": 30000,
        "guideMinimumDuration": 30000,
        "stealth": False,
        "streamMode": "hls",
        "transcodeConfigId": TC,
        "subtitlesEnabled": False,
        "startTime": now,
        "offline": {"picture": "", "soundtrack": "", "mode": "pic"},
        # Seinfeld primary art as a stand-in sitcom icon
        "icon": {
            "path": "http://jellyfin:8096/Items/f6795b7783fd8d2c58f1833a9464efae/Images/Primary",
            "width": 0,
            "duration": 0,
            "position": "bottom-right",
            "useDefaultIconFallback": True,
        },
        "watermark": {
            "enabled": False,
            "position": "bottom-right",
            "width": 10,
            "verticalMargin": 1,
            "horizontalMargin": 1,
            "duration": 0,
            "fixedSize": False,
            "animated": False,
            "opacity": 100,
        },
        "onDemand": {"enabled": False},
        "fillerCollections": [],
    }


def build_schedule() -> dict:
    slots = []
    for i, (_title, show_id) in enumerate(SHOWS):
        slots.append(
            {
                "id": str(uuid.uuid4()),
                "type": "show",
                "showId": show_id,
                "order": "shuffle",
                "direction": "asc",
                "cooldownMs": 0,
                "weight": 100,
                "durationSpec": {"type": "dynamic", "programCount": 1},
                "index": i,
            }
        )
    return {
        "type": "random",
        "flexPreference": "distribute",
        "maxDays": MAX_DAYS,
        "padMs": 1,
        "padStyle": "slot",
        "randomDistribution": "uniform",
        "lockWeights": False,
        "timeZoneOffset": TZ_OFFSET_MIN,
        "slots": slots,
    }


def apply_programming(channel_id: str) -> int:
    schedule = build_schedule()
    preview = api(
        "POST",
        f"/channels/{channel_id}/schedule-slots",
        {"schedule": schedule},
    )
    programs = preview.get("programs") or {}
    if isinstance(programs, dict):
        prog_ids = list(programs.keys())
    else:
        prog_ids = [p["id"] for p in programs if p.get("id")]
    api(
        "POST",
        f"/channels/{channel_id}/programming",
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
    existing = find_channel()
    if existing:
        cid = existing["id"]
        body = channel_body(cid)
        api("PUT", f"/channels/{cid}", {"channel": body})
        print(f"Updated #{CHANNEL_NUMBER} {CHANNEL_NAME} ({cid})")
    else:
        body = channel_body()
        created = api("POST", "/channels", {"type": "new", "channel": body})
        cid = (created or {}).get("id") or body["id"]
        print(f"Created #{CHANNEL_NUMBER} {CHANNEL_NAME} ({cid})")

    n = apply_programming(cid)
    print(f"  schedule: {len(SHOWS)} equal-weight show slots, lineup≈{n}")

    try:
        api("POST", "/tasks/UpdateXmlTvTask/run")
        print("  UpdateXmlTvTask queued — refresh Live TV guide in Jellyfin")
    except SystemExit as e:
        print(f"  XMLTV task: {e}")


if __name__ == "__main__":
    main()
