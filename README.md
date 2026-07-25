# Homelab

Monorepo for home infrastructure: monitoring stack, exporters, and Mac-side tooling.

## Monitoring stack

Deploy to Raspberry Pi:
```bash
./deploy-to-pi.sh wmichelin raspberrypi.local
```

Deploy exporters to G5 (node-exporter, smartctl-exporter, SnapRAID + Docker textfile metrics):
```bash
./deploy-exporters-to-g5.sh g5 wmichelin
```

### Access

- Grafana: http://raspberrypi.local:3000 (Homelab → **Homelab Monitoring**)
- Prometheus targets: http://raspberrypi.local:9090/targets

### G5 notes

- Exporters listen on `192.168.0.54:9100` (node) and `:9633` (SMART).
- SnapRAID status/job metrics and Docker CPU/mem are written under `~/homelab-exporters/textfile/` by user systemd timers.
- If `snapraid_status_ok` is 0, check `snapraid status` on g5 (currently fails if a configured content dir is missing, e.g. `/mnt/tm/marissa/.snapraid/`).
- Immich: `~/networked-storage/immich/` on g5, UI at http://192.168.0.54:2283 — blackbox probes `/api/server/ping` (Media stack panel).

## Apple Photos export

Mac scripts that export the Photos library to SnapRAID (`/Volumes/safe`) via [osxphotos](https://github.com/RhetTbull/osxphotos), with Live Photo companion `.mov` files in a parallel tree.

See [`apple-photos-export/README.md`](apple-photos-export/README.md).

```bash
cd apple-photos-export
cp config.example.env config.env   # once; gitignored
./export-photos.sh
./check-integrity.py               # use osxphotos' python if needed
```
