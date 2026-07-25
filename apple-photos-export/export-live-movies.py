#!/usr/bin/env python3
"""Export only Live Photo companion .mov files.

Stills stay in Photos/ (osxphotos export --skip-live).
Layout:
  Live Photos/{year}/{mm}/{YYYYMMDD-HHMMSS}_{original_stem}[_edited].mov

Paths default from environment (see config.example.env) or CLI flags.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

import osxphotos


def env_path(name: str, default: Path | None = None) -> Path | None:
    raw = os.environ.get(name)
    if raw:
        return Path(raw).expanduser()
    return default


def default_dest() -> Path | None:
    explicit = env_path("LIVE_DEST")
    if explicit:
        return explicit
    root = env_path("PHOTOS_EXPORT_ROOT")
    if root:
        return root / "Live Photos"
    return None


def default_library() -> Path:
    return env_path(
        "PHOTOS_LIBRARY",
        Path.home() / "Pictures" / "Photos Library.photoslibrary",
    )  # type: ignore[return-value]


def default_state() -> Path:
    support = env_path(
        "OSXPHOTOS_SUPPORT",
        Path.home() / "Library" / "Application Support" / "osxphotos",
    )
    preferred = env_path("LIVE_MOVIES_STATE", support / "live-movies.json")  # type: ignore[operator]
    if preferred and preferred.exists():
        return preferred
    legacy = support / "safe-live-movies.json"  # type: ignore[operator]
    if legacy.exists() and preferred and not preferred.exists():
        preferred.parent.mkdir(parents=True, exist_ok=True)
        legacy.rename(preferred)
        print(f"Renamed {legacy.name} → {preferred.name}", file=sys.stderr)
    return preferred  # type: ignore[return-value]


def dest_relpath(photo: osxphotos.PhotoInfo, edited: bool) -> Path:
    created = photo.date
    stem = Path(photo.original_filename).stem
    edited_suffix = "_edited" if edited else ""
    name = f"{created.strftime('%Y%m%d-%H%M%S')}_{stem}{edited_suffix}.mov"
    return Path(f"{created.year:04d}") / f"{created.month:02d}" / name


def file_digest(path: Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_state(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text())
    return {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=0, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, default=None)
    parser.add_argument("--library", type=Path, default=None)
    parser.add_argument("--state", type=Path, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    # Ignore unknown args so export-photos.sh can forward osxphotos flags harmlessly
    args, _unknown = parser.parse_known_args()

    dest = args.dest or default_dest()
    library = args.library or default_library()
    state_path = args.state or default_state()

    if dest is None:
        print(
            "error: set --dest or PHOTOS_EXPORT_ROOT / LIVE_DEST",
            file=sys.stderr,
        )
        return 1
    if not library.exists():
        print(f"error: library not found: {library}", file=sys.stderr)
        return 1

    print(f"Library: {library}")
    print(f"Dest:    {dest}")
    print(f"State:   {state_path}")
    if args.dry_run:
        print("Mode:    dry-run")
    print()

    state = load_state(state_path)
    db = osxphotos.PhotosDB(dbfile=str(library))

    exported = skipped = missing = errors = 0
    for photo in db.photos():
        if not photo.live_photo:
            continue

        candidates = []
        if photo.path_live_photo:
            candidates.append((Path(photo.path_live_photo), False))
        if photo.path_edited_live_photo:
            candidates.append((Path(photo.path_edited_live_photo), True))

        if not candidates:
            missing += 1
            if args.verbose:
                print(f"MISSING live movie: {photo.original_filename} ({photo.uuid})")
            continue

        for src, edited in candidates:
            if not src.exists():
                missing += 1
                if args.verbose:
                    print(f"MISSING file: {src}")
                continue

            rel = dest_relpath(photo, edited)
            dest_file = dest / rel
            key = f"{photo.uuid}:{'edited' if edited else 'original'}"
            digest = file_digest(src)
            prev = state.get(key)

            if (
                prev
                and prev.get("path") == str(rel)
                and prev.get("digest") == digest
                and dest_file.exists()
            ):
                skipped += 1
                continue

            if args.verbose or args.dry_run:
                action = "WOULD EXPORT" if args.dry_run else "EXPORT"
                print(f"{action}: {rel}")

            if args.dry_run:
                exported += 1
                continue

            try:
                dest_file.parent.mkdir(parents=True, exist_ok=True)
                if dest_file.exists() and file_digest(dest_file) == digest:
                    skipped += 1
                else:
                    shutil.copy2(src, dest_file)
                    exported += 1
                state[key] = {"path": str(rel), "digest": digest, "uuid": photo.uuid}
            except OSError as e:
                errors += 1
                print(f"ERROR {rel}: {e}", file=sys.stderr)

    if not args.dry_run:
        save_state(state_path, state)

    print()
    print(f"Exported/updated: {exported}")
    print(f"Skipped (unchanged): {skipped}")
    print(f"Missing live movies: {missing}")
    print(f"Errors: {errors}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
