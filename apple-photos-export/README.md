# Apple Photos Export

Part of the [homelab](../) monorepo. Scriptable export of an Apple Photos library to a folder tree (NAS, external disk, etc.) using [osxphotos](https://github.com/RhetTbull/osxphotos).

Live Photo **stills** stay with normal photos; companion **`.mov`** files go to a parallel tree so gallery apps treat stills as images.

## Layout

```
$PHOTOS_EXPORT_ROOT/
  Photos/YYYY/MM/...       # stills (incl. Live Photo HEIC/JPG) + real videos
  Live Photos/YYYY/MM/...  # Live Photo companion .mov only
```

Filenames: `{YYYYMMDD-HHMMSS}_{original_name}`.

## Requirements

- macOS with a Photos library
- [osxphotos](https://github.com/RhetTbull/osxphotos) (`brew install osxphotos` or `uv tool install osxphotos`)
- `exiftool` (used by the export pass)
- `sqlite3` (used by the Live Photo migration scrub)
- **Full Disk Access** for Terminal (or whatever runs the scripts) so Photos library files are readable

## Configure

```bash
cp config.example.env config.env
# edit PHOTOS_EXPORT_ROOT=...
```

`config.env` is gitignored. You can also export the same variables in your shell.

| Variable | Purpose |
|----------|---------|
| `PHOTOS_EXPORT_ROOT` | Root folder (creates `Photos/` and `Live Photos/`) |
| `PHOTOS_LIBRARY` | Photos library path (default: `~/Pictures/Photos Library.photoslibrary`) |
| `PHOTOS_EXPORT_DB` | osxphotos export DB (default under `~/Library/Application Support/osxphotos/`) |
| `LIVE_MOVIES_STATE` | JSON state for Live movie copies |

## Run

Always run from **Terminal.app** (Full Disk Access).

### Fresh export

```bash
./export-photos.sh
```

Safe to interrupt and re-run: pass 1 uses `--update` + an export DB; pass 2 skips unchanged Live movies via digest state.

### One-time: split already-exported Live movies

If companion `.mov` files were previously written into `Photos/`:

```bash
./migrate-live-photos.sh              # dry-run
./migrate-live-photos.sh --execute    # move .mov only + scrub export DB
./export-photos.sh                    # resume
```

### Integrity check

Compare the local library to the export (DB + files on disk):

```bash
# use the same Python that has osxphotos installed
"$(dirname "$(command -v osxphotos)")/python" ./check-integrity.py
```

Optional: `--verbose`, `--json report.json`, `--limit-examples 30`.

## Scripts

| Script | Role |
|--------|------|
| `export-photos.sh` | Pass 1: osxphotos `--skip-live` → Photos; Pass 2: Live `.mov` → Live Photos |
| `export-live-movies.py` | Copy Live Photo companion movies only |
| `migrate-live-photos.sh` | Move paired `.mov` out of an existing Photos tree |
| `check-integrity.py` | Library vs export DB/files report |
| `lib/config.sh` | Shared env / `config.env` loading |

## Notes

- **Missing live movie** during pass 2 usually means the companion isn’t downloaded locally (iCloud-only). Re-run after Photos has downloaded originals, or keep `--download-missing` on pass 1.
- Some assets labeled `.HEIC` may actually be JPEG; exiftool can warn and osxphotos may retry/fail those rows — check the report CSV / integrity script.
- Export state lives on the Mac (not in this repo): the osxphotos SQLite DB and `live-movies.json`.

## License

MIT
