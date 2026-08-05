#!/usr/bin/env python3
"""Create Tunarr smart collections for genres / decades / mixes (no channel wiring)."""

from __future__ import annotations

import json
import urllib.error
import urllib.request

API = "http://127.0.0.1:8000/api"

MAJOR = [
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
MEDIUM = [
    "Romance",
    "Mystery",
    "Family",
    "Animation",
    "War",
    "History",
]
DECADES = [1990, 2000, 2010, 2020]
MIXES = [
    ("Action + Adventure", ["Action", "Adventure"]),
    ("Scary Night", ["Horror", "Thriller"]),
    ("Brain Food", ["Drama", "Mystery"]),
    ("Escape Hatch", ["Fantasy", "Science Fiction", "Adventure"]),
    ("Laugh Track", ["Comedy", "Family", "Animation"]),
]

CLASSICS_MAX_YEAR = 2005
FRESH_MIN_YEAR = 2015


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
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise SystemExit(
            f"{method} {path} → {e.code}: {e.read().decode()[:500]}"
        ) from e


def genre_eq(genre: str) -> dict:
    return {
        "type": "value",
        "fieldSpec": {
            "key": "genres.name",
            "name": "genre",
            "type": "faceted_string",
            "op": "=",
            "value": [genre],
        },
    }


def year_op(op: str, value) -> dict:
    return {
        "type": "value",
        "fieldSpec": {
            "key": "originalReleaseYear",
            "name": "year",
            "type": "numeric",
            "op": op,
            "value": value,
        },
    }


def and_filters(*nodes: dict) -> dict:
    return {"type": "op", "op": "and", "children": list(nodes)}


def or_filters(*nodes: dict) -> dict:
    return {"type": "op", "op": "or", "children": list(nodes)}


def short(g: str) -> str:
    return "Sci-Fi" if g == "Science Fiction" else g


def upsert(name: str, filter_obj: dict, filter_string: str) -> None:
    existing = {c["name"]: c for c in (api("GET", "/smart_collections") or [])}
    body = {
        "name": name,
        "filter": filter_obj,
        "filterString": filter_string,
        "keywords": "",
    }
    if name in existing:
        api("PUT", f"/smart_collections/{existing[name]['uuid']}", body)
        print(f"  updated  {name}")
    else:
        api("POST", "/smart_collections", body)
        print(f"  created  {name}")


def main() -> None:
    # Clean leftover TEST collections
    for c in api("GET", "/smart_collections") or []:
        if c["name"].startswith("TEST"):
            api("DELETE", f"/smart_collections/{c['uuid']}")
            print(f"  deleted  {c['name']}")

    print("Genre pools…")
    for g in MAJOR + MEDIUM:
        upsert(short(g), genre_eq(g), f'genre = "{g}"')

    print("Genre Classics (year ≤ %d)…" % CLASSICS_MAX_YEAR)
    for g in MAJOR:
        upsert(
            f"{short(g)} Classics",
            and_filters(genre_eq(g), year_op("<=", CLASSICS_MAX_YEAR)),
            f'genre = "{g}" AND year <= {CLASSICS_MAX_YEAR}',
        )

    print("Genre Fresh (year ≥ %d)…" % FRESH_MIN_YEAR)
    for g in MAJOR + MEDIUM:
        upsert(
            f"{short(g)} Fresh",
            and_filters(genre_eq(g), year_op(">=", FRESH_MIN_YEAR)),
            f'genre = "{g}" AND year >= {FRESH_MIN_YEAR}',
        )

    print("Decades…")
    for decade in DECADES:
        upsert(
            f"{decade}s",
            year_op("to", [decade, decade + 9]),
            f"year between [{decade}, {decade + 9}]",
        )

    print("Mixes…")
    for name, genres in MIXES:
        upsert(
            name,
            or_filters(*[genre_eq(g) for g in genres]),
            " OR ".join(f'genre = "{g}"' for g in genres),
        )

    all_sc = api("GET", "/smart_collections") or []
    print(f"Done: {len(all_sc)} smart collections total")
    for c in sorted(all_sc, key=lambda x: x["name"]):
        print(f"  - {c['name']}: {c.get('filterString')}")


if __name__ == "__main__":
    main()
