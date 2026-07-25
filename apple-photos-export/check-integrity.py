#!/usr/bin/env python3
"""Integrity check: local Apple Photos library vs export destinations.

Compares library assets to:
  - osxphotos export DB + files under Photos/
  - live-movie state JSON + files under Live Photos/

Run from Terminal.app (Full Disk Access). Paths from CLI or environment
(see config.example.env).
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from collections import Counter
from pathlib import Path

import osxphotos


def env_path(name: str, default: Path | None = None) -> Path | None:
    raw = os.environ.get(name)
    if raw:
        return Path(raw).expanduser()
    return default


def default_library() -> Path:
    return env_path(
        "PHOTOS_LIBRARY",
        Path.home() / "Pictures" / "Photos Library.photoslibrary",
    )  # type: ignore[return-value]


def default_photos_dest() -> Path | None:
    explicit = env_path("PHOTOS_DEST")
    if explicit:
        return explicit
    root = env_path("PHOTOS_EXPORT_ROOT")
    if root:
        return root / "Photos"
    return None


def default_live_dest() -> Path | None:
    explicit = env_path("LIVE_DEST")
    if explicit:
        return explicit
    root = env_path("PHOTOS_EXPORT_ROOT")
    if root:
        return root / "Live Photos"
    return None


def default_support() -> Path:
    return env_path(
        "OSXPHOTOS_SUPPORT",
        Path.home() / "Library" / "Application Support" / "osxphotos",
    )  # type: ignore[return-value]


def default_photos_db() -> Path:
    support = default_support()
    preferred = env_path("PHOTOS_EXPORT_DB", support / "photos-export.db")
    if preferred and preferred.exists():
        return preferred
    for legacy_name in ("safe-photos.db", "safe-export.db"):
        legacy = support / legacy_name
        if legacy.exists() and preferred and not preferred.exists():
            preferred.parent.mkdir(parents=True, exist_ok=True)
            legacy.rename(preferred)
            for suffix in ("-shm", "-wal"):
                side = Path(str(legacy) + suffix)
                if side.exists():
                    side.rename(Path(str(preferred) + suffix))
            print(f"Renamed {legacy.name} → {preferred.name}", file=sys.stderr)
            return preferred  # type: ignore[return-value]
    return preferred  # type: ignore[return-value]


def default_live_state() -> Path:
    support = default_support()
    preferred = env_path("LIVE_MOVIES_STATE", support / "live-movies.json")
    if preferred and preferred.exists():
        return preferred
    legacy = support / "safe-live-movies.json"
    if legacy.exists() and preferred and not preferred.exists():
        preferred.parent.mkdir(parents=True, exist_ok=True)
        legacy.rename(preferred)
        print(f"Renamed {legacy.name} → {preferred.name}", file=sys.stderr)
    return preferred  # type: ignore[return-value]


def live_relpath(photo: osxphotos.PhotoInfo, edited: bool = False) -> Path:
    created = photo.date
    stem = Path(photo.original_filename).stem
    suffix = "_edited" if edited else ""
    name = f"{created.strftime('%Y%m%d-%H%M%S')}_{stem}{suffix}.mov"
    return Path(f"{created.year:04d}") / f"{created.month:02d}" / name


def load_export_db(db_path: Path) -> dict[str, list[dict]]:
    """uuid -> list of export_data rows."""
    if not db_path.exists():
        return {}
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT uuid, filepath, filepath_normalized, dest_size, error FROM export_data"
    ).fetchall()
    conn.close()
    by_uuid: dict[str, list[dict]] = {}
    for r in rows:
        by_uuid.setdefault(r["uuid"], []).append(dict(r))
    return by_uuid


def load_live_state(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text())
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, default=None)
    parser.add_argument("--photos-dest", type=Path, default=None)
    parser.add_argument("--live-dest", type=Path, default=None)
    parser.add_argument("--photos-db", type=Path, default=None)
    parser.add_argument("--live-state", type=Path, default=None)
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--json", type=Path, help="Write full report JSON to this path")
    parser.add_argument(
        "--limit-examples",
        type=int,
        default=15,
        help="Max example paths to print per category (default 15)",
    )
    args = parser.parse_args()

    library = args.library or default_library()
    photos_dest = args.photos_dest or default_photos_dest()
    live_dest = args.live_dest or default_live_dest()
    photos_db = args.photos_db or default_photos_db()
    live_state_path = args.live_state or default_live_state()

    if photos_dest is None or live_dest is None:
        print(
            "error: set --photos-dest/--live-dest or PHOTOS_EXPORT_ROOT",
            file=sys.stderr,
        )
        return 1
    if not library.exists():
        print(f"error: library not found: {library}", file=sys.stderr)
        return 1
    if not photos_dest.exists():
        print(f"error: Photos dest not found: {photos_dest}", file=sys.stderr)
        return 1

    print(f"Library:    {library}")
    print(f"Photos:     {photos_dest}")
    print(f"Live:       {live_dest}")
    print(f"Export DB:  {photos_db}")
    print(f"Live state: {live_state_path}")
    print()
    print("Loading Photos library…")
    db = osxphotos.PhotosDB(dbfile=str(library))
    photos = list(db.photos())
    print(f"Library assets: {len(photos)}")

    print("Loading export database…")
    export_by_uuid = load_export_db(photos_db)
    live_state = load_live_state(live_state_path)

    counts: Counter = Counter()
    examples: dict[str, list[str]] = {
        "not_in_export_db": [],
        "export_path_missing": [],
        "export_had_error": [],
        "live_movie_missing_icloud": [],
        "live_movie_expected_absent": [],
        "live_movie_ok": [],
    }

    report_assets = []

    for photo in photos:
        info = {
            "uuid": photo.uuid,
            "filename": photo.original_filename,
            "date": photo.date.isoformat() if photo.date else None,
            "live_photo": bool(photo.live_photo),
            "ismovie": bool(photo.ismovie),
        }
        counts["library_assets"] += 1

        rows = export_by_uuid.get(photo.uuid, [])
        if not rows:
            counts["not_in_export_db"] += 1
            if len(examples["not_in_export_db"]) < args.limit_examples:
                examples["not_in_export_db"].append(
                    f"{photo.original_filename} ({photo.uuid})"
                )
            info["export"] = "missing_from_db"
        else:
            counts["in_export_db"] += 1
            missing_paths = []
            had_error = False
            for row in rows:
                fp = photos_dest / row["filepath"]
                if row.get("error"):
                    had_error = True
                if not fp.exists():
                    missing_paths.append(row["filepath"])
            if had_error:
                counts["export_had_error"] += 1
                if len(examples["export_had_error"]) < args.limit_examples:
                    examples["export_had_error"].append(
                        f"{photo.original_filename} ({photo.uuid})"
                    )
            if missing_paths:
                counts["export_path_missing"] += 1
                if len(examples["export_path_missing"]) < args.limit_examples:
                    examples["export_path_missing"].append(
                        f"{photo.original_filename}: {missing_paths[0]}"
                    )
                info["export"] = "db_ok_file_missing"
                info["missing_paths"] = missing_paths
            else:
                counts["export_files_ok"] += 1
                info["export"] = "ok"

        if photo.live_photo:
            counts["live_photos"] += 1
            has_local = bool(
                (photo.path_live_photo and Path(photo.path_live_photo).exists())
                or (
                    photo.path_edited_live_photo
                    and Path(photo.path_edited_live_photo).exists()
                )
            )
            key = f"{photo.uuid}:original"
            state = live_state.get(key) or live_state.get(f"{photo.uuid}:edited")
            expected = live_dest / live_relpath(photo, edited=False)
            state_path = None
            if state and state.get("path"):
                state_path = live_dest / state["path"]

            present = expected.exists() or (state_path is not None and state_path.exists())

            if present:
                counts["live_movie_on_nas"] += 1
                info["live_movie"] = "ok"
            elif not has_local:
                counts["live_movie_missing_icloud"] += 1
                info["live_movie"] = "not_local_in_library"
                if len(examples["live_movie_missing_icloud"]) < args.limit_examples:
                    examples["live_movie_missing_icloud"].append(
                        f"{photo.original_filename} ({photo.uuid})"
                    )
            else:
                counts["live_movie_expected_absent"] += 1
                info["live_movie"] = "local_but_not_on_nas"
                if len(examples["live_movie_expected_absent"]) < args.limit_examples:
                    examples["live_movie_expected_absent"].append(
                        f"{photo.original_filename} → {live_relpath(photo)}"
                    )

        report_assets.append(info)

    library_uuids = {p.uuid for p in photos}
    orphan_db = 0
    orphan_examples = []
    for uuid, rows in export_by_uuid.items():
        if uuid not in library_uuids:
            orphan_db += 1
            if len(orphan_examples) < args.limit_examples:
                orphan_examples.append(f"{uuid}: {rows[0]['filepath']}")
    counts["export_db_orphan_uuids"] = orphan_db

    live_state_missing = 0
    live_state_missing_ex = []
    for key, st in live_state.items():
        p = live_dest / st["path"]
        if not p.exists():
            live_state_missing += 1
            if len(live_state_missing_ex) < args.limit_examples:
                live_state_missing_ex.append(st["path"])
    counts["live_state_file_missing"] = live_state_missing

    print()
    print("=== Summary ===")
    print(f"Library assets:                  {counts['library_assets']}")
    print(f"In Photos export DB:             {counts['in_export_db']}")
    print(f"  files present on disk:         {counts['export_files_ok']}")
    print(f"  DB entry but file missing:     {counts['export_path_missing']}")
    print(f"  export recorded error:         {counts['export_had_error']}")
    print(f"Not in Photos export DB:         {counts['not_in_export_db']}")
    print(f"Export DB UUIDs not in library:  {counts['export_db_orphan_uuids']}")
    print()
    print(f"Live Photos (library):           {counts['live_photos']}")
    print(f"  companion .mov on disk:        {counts['live_movie_on_nas']}")
    print(f"  not downloaded locally:        {counts['live_movie_missing_icloud']}")
    print(f"  local but missing on disk:     {counts['live_movie_expected_absent']}")
    print(f"Live state points to missing:    {counts['live_state_file_missing']}")
    print(f"Live state entries:              {len(live_state)}")

    def dump_examples(title: str, items: list[str]) -> None:
        if not items:
            return
        print()
        print(f"--- {title} (up to {args.limit_examples}) ---")
        for line in items:
            print(f"  {line}")

    dump_examples("Not in export DB", examples["not_in_export_db"])
    dump_examples("Export DB path missing on disk", examples["export_path_missing"])
    dump_examples("Export had error", examples["export_had_error"])
    dump_examples("Live movie not local (iCloud)", examples["live_movie_missing_icloud"])
    dump_examples(
        "Live movie local but not on disk", examples["live_movie_expected_absent"]
    )
    dump_examples("Export DB orphan UUIDs", orphan_examples)
    dump_examples("Live state file missing", live_state_missing_ex)

    if args.verbose:
        print()
        print("(verbose: per-asset detail omitted; use --json for full dump)")

    payload = {
        "counts": dict(counts),
        "examples": examples,
        "orphan_examples": orphan_examples,
        "live_state_missing_examples": live_state_missing_ex,
        "assets": report_assets if args.json else None,
    }
    if args.json:
        payload["assets"] = report_assets
        args.json.write_text(json.dumps(payload, indent=2))
        print()
        print(f"Wrote {args.json}")

    problems = (
        counts["export_path_missing"]
        + counts["not_in_export_db"]
        + counts["live_movie_expected_absent"]
        + counts["live_state_file_missing"]
    )
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
