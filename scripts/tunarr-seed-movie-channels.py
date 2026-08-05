#!/usr/bin/env python3
"""Seed many Tunarr movie channels: genre × variant (+ decades).

Variants per genre (when enough titles):
  Shuffle  — random cycle
  Classics — oldest year first
  Fresh    — newest year first

Run on G5:  python3 scripts/tunarr-seed-movie-channels.py
"""

from __future__ import annotations

import copy
import json
import random
import subprocess
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

BASE = "http://127.0.0.1:8000/api"
MS = "9749c319-8def-406e-91f2-8f074beba17a"
MOV = "a80b9b4f-c986-4784-9282-2e0b3ec87559"
TC = "595a6a45-be24-4ee5-8934-9f50a8f8100a"

# Genres with enough library depth for multiple variants.
MAJOR_GENRES = [
    "Action",
    "Drama",
    "Science Fiction",
    "Adventure",
    "Thriller",
    "Comedy",
    "Crime",
    "Fantasy",
    "Horror",
]
# Two variants only.
MEDIUM_GENRES = [
    "Romance",
    "Mystery",
    "Family",
    "Animation",
    "War",
    "History",
]
DECADE_CHANNELS = [1990, 2000, 2010, 2020]
MIN_PROGRAMS = 8


@dataclass
class Movie:
    uuid: str
    title: str
    duration: int
    year: int | None
    genres: set[str]
    external_key: str


def api(method: str, path: str, body=None):
    # Tunarr DELETE requires a JSON body when Content-Type is application/json.
    if body is None and method in ("DELETE", "POST", "PUT", "PATCH"):
        body = {}
    data = None if body is None else json.dumps(body).encode()
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:2000]
        raise SystemExit(f"{method} {path} → {e.code}: {detail}") from e


def fetch_all_jellyfin_movies() -> list[dict]:
    items: list[dict] = []
    offset, page = 0, 100
    while True:
        q = urllib.parse.urlencode(
            {
                "itemTypes": "Movie",
                "recursive": "true",
                "limit": page,
                "offset": offset,
                "sortBy": "SortName",
            }
        )
        d = api("GET", f"/jellyfin/{MS}/libraries/{MOV}/items?{q}")
        batch = d.get("result") or []
        items.extend(batch)
        total = d.get("total", len(items))
        offset += len(batch)
        if not batch or offset >= total:
            break
    return items


def resolve_movies(jellyfin_items: list[dict]) -> list[Movie]:
    keys = [it["externalId"] for it in jellyfin_items if it.get("externalId")]
    keys_json = json.dumps(keys)
    py = r"""
import json, sqlite3, sys
keys = json.loads(sys.argv[1])
con = sqlite3.connect("/config/tunarr/db.db")
con.row_factory = sqlite3.Row
q = ",".join("?" for _ in keys)
rows = con.execute(
    f"SELECT uuid, title, duration, external_key, year FROM program "
    f"WHERE type='movie' AND external_key IN ({q})",
    keys,
).fetchall()
print(json.dumps([dict(r) for r in rows]))
"""
    out = subprocess.check_output(
        ["docker", "exec", "-i", "tunarr", "python3", "-c", py, keys_json],
        text=True,
    )
    by_key = {r["external_key"]: r for r in json.loads(out)}
    movies: list[Movie] = []
    for it in jellyfin_items:
        ext = it.get("externalId")
        row = by_key.get(ext) if ext else None
        if not row or not row.get("duration"):
            continue
        genres = set()
        for g in it.get("genres") or []:
            name = g.get("name") if isinstance(g, dict) else str(g)
            if name:
                genres.add(name)
        movies.append(
            Movie(
                uuid=row["uuid"],
                title=row["title"],
                duration=int(row["duration"]),
                year=row.get("year") or it.get("year"),
                genres=genres,
                external_key=ext,
            )
        )
    # de-dupe by uuid
    seen: set[str] = set()
    unique: list[Movie] = []
    for m in movies:
        if m.uuid in seen:
            continue
        seen.add(m.uuid)
        unique.append(m)
    return unique


def channel_shell(template: dict, name: str, number: int, start_ms: int) -> dict:
    ch = copy.deepcopy(template)
    for k in ("programCount", "sessions", "fallback", "id"):
        ch.pop(k, None)
    ch["duration"] = 0
    ch["name"] = name
    ch["number"] = number
    ch["groupTitle"] = "Movies"
    ch["transcodeConfigId"] = TC
    ch["streamMode"] = ch.get("streamMode") or "hls"
    ch["startTime"] = start_ms
    ch["guideMinimumDuration"] = ch.get("guideMinimumDuration") or 30000
    ch["disableFillerOverlay"] = bool(ch.get("disableFillerOverlay", False))
    ch["stealth"] = False
    ch["subtitlesEnabled"] = bool(ch.get("subtitlesEnabled", False))
    ch.setdefault("offline", {"picture": "", "soundtrack": "", "mode": "pic"})
    ch.setdefault(
        "icon",
        {
            "path": "",
            "width": 0,
            "duration": 0,
            "position": "bottom-right",
            "useDefaultIconFallback": True,
        },
    )
    ch.setdefault(
        "watermark",
        {
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
    )
    ch.setdefault("onDemand", {"enabled": False})
    ch.setdefault("fillerCollections", [])
    ch.setdefault("fillerRepeatCooldown", 30000)
    return ch


def set_lineup(channel_id: str, movies: list[Movie]) -> None:
    lineup = [
        {"type": "content", "id": m.uuid, "duration": m.duration} for m in movies
    ]
    api(
        "POST",
        f"/channels/{channel_id}/programming",
        {"type": "manual", "lineup": lineup, "append": False},
    )


def order_movies(movies: list[Movie], mode: str, seed: int) -> list[Movie]:
    ms = list(movies)
    if mode == "shuffle":
        rng = random.Random(seed)
        rng.shuffle(ms)
    elif mode == "classics":
        ms.sort(key=lambda m: (m.year is None, m.year or 9999, m.title.lower()))
    elif mode == "fresh":
        ms.sort(
            key=lambda m: (m.year is None, -(m.year or 0), m.title.lower())
        )
    else:
        raise ValueError(mode)
    return ms


def short_genre(name: str) -> str:
    return {
        "Science Fiction": "Sci-Fi",
    }.get(name, name)


def build_plan(movies: list[Movie]) -> list[tuple[str, list[Movie], str, int]]:
    """Return list of (channel_name, movies, mode, seed)."""
    plan: list[tuple[str, list[Movie], str, int]] = []
    seed_base = 4242

    def by_genre(g: str) -> list[Movie]:
        return [m for m in movies if g in m.genres]

    for i, g in enumerate(MAJOR_GENRES):
        pool = by_genre(g)
        if len(pool) < MIN_PROGRAMS:
            continue
        label = short_genre(g)
        plan.append((f"{label} Shuffle", pool, "shuffle", seed_base + i * 10))
        plan.append((f"{label} Classics", pool, "classics", 0))
        plan.append((f"{label} Fresh", pool, "fresh", 0))

    for i, g in enumerate(MEDIUM_GENRES):
        pool = by_genre(g)
        if len(pool) < MIN_PROGRAMS:
            continue
        label = short_genre(g)
        plan.append(
            (f"{label} Shuffle", pool, "shuffle", seed_base + 200 + i * 10)
        )
        plan.append((f"{label} Fresh", pool, "fresh", 0))

    for i, decade in enumerate(DECADE_CHANNELS):
        pool = [
            m
            for m in movies
            if m.year is not None and decade <= m.year < decade + 10
        ]
        if len(pool) < MIN_PROGRAMS:
            continue
        plan.append(
            (f"{decade}s Shuffle", pool, "shuffle", seed_base + 400 + i)
        )
        plan.append((f"{decade}s Fresh", pool, "fresh", 0))

    # Mix channels for variety while flipping
    mixes = [
        ("Action + Adventure", {"Action", "Adventure"}),
        ("Scary Night", {"Horror", "Thriller"}),
        ("Brain Food", {"Drama", "Mystery"}),
        ("Escape Hatch", {"Fantasy", "Science Fiction", "Adventure"}),
        ("Laugh Track", {"Comedy", "Family", "Animation"}),
    ]
    for i, (name, gs) in enumerate(mixes):
        pool = [m for m in movies if m.genres & gs]
        # Prefer titles that hit at least one; de-dupe already done
        if len(pool) < MIN_PROGRAMS:
            continue
        plan.append((name, pool, "shuffle", seed_base + 600 + i))

    return plan


def delete_all_channels(channels: list[dict]) -> None:
    # Delete highest numbers first to avoid renumber side effects
    for c in sorted(channels, key=lambda x: x["number"], reverse=True):
        cid = c["id"]
        try:
            api("DELETE", f"/channels/{cid}")
            print(f"  deleted #{c['number']} {c['name']}")
        except SystemExit as e:
            print(f"  skip delete {cid}: {e}")


def main() -> None:
    print("Loading library…")
    jf = fetch_all_jellyfin_movies()
    movies = resolve_movies(jf)
    print(f"  {len(movies)} Tunarr-resolved movies")

    plan = build_plan(movies)
    print(f"Planning {len(plan)} channels")

    existing = api("GET", "/channels") or []
    print(f"Removing {len(existing)} existing channels…")
    delete_all_channels(existing)

    # Need a template channel — create a throwaway then reshape, or POST new.
    # Tunarr requires a channel body; use minimal from docs / prior channel shape.
    now = int(time.time() * 1000)
    template = {
        "name": "tmp",
        "number": 1,
        "groupTitle": "Movies",
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
        "icon": {
            "path": "",
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

    # Stagger start times so "now" lands mid-different films when flipping.
    stagger_ms = 47 * 60 * 1000  # 47 minutes between channel clocks

    for idx, (name, pool, mode, seed) in enumerate(plan):
        number = idx + 1
        ordered = order_movies(pool, mode, seed)
        start_ms = now - (idx * stagger_ms)
        body = channel_shell(template, name, number, start_ms)
        body["id"] = str(uuid.uuid4())
        created = api("POST", "/channels", {"type": "new", "channel": body})
        cid = created.get("id") or body["id"]
        set_lineup(cid, ordered)
        hrs = sum(m.duration for m in ordered) / 3_600_000
        print(
            f"#{number:02d} {name}: {len(ordered)} titles, "
            f"{hrs:.0f}h cycle ({mode})"
        )

    # Refresh XMLTV
    try:
        api("POST", "/tasks/UpdateXmlTvTask/run")
        print("Triggered UpdateXmlTvTask")
    except SystemExit as e:
        print(f"XMLTV task: {e}")

    chs = api("GET", "/channels") or []
    print(f"Done: {len(chs)} channels")


if __name__ == "__main__":
    main()
