# Homelab

Monorepo for home infrastructure: Raspberry Pi monitoring, G5 storage/media stack, exporters, and Mac-side tooling.

**Canonical clone:** this repo (`github.com/wmichelin/homelab`).  
**G5 live root:** `~/code/homelab` (deployment checkout). Compat symlinks on G5: `~/networked-storage` → repo root, `~/homelab-exporters` → `apps/exporters`.

## Layout

| Path | Contents |
|------|----------|
| `apps/media-stack/` | Jellyfin, Radarr, Lidarr, qBittorrent, Prowlarr (G5) |
| `apps/immich/` | Immich + ML / CUDA (G5) |
| `apps/exporters/` | node-exporter, SMART, docker/netdev textfile metrics (G5) |
| `infra/storage/` | fstab / SnapRAID / Samba snapshots + setup scripts |
| `infra/systemd/` | system + user unit files for G5 |
| `scripts/` | G5 backups, Proton→qBit port sync, unit installer |
| `docs/` | G5 runbooks |
| `secrets/` | passwords on G5 only (mode 600, gitignored) |
| `docker-compose.yml`, `grafana/`, `prometheus/`, … | Pi monitoring stack |
| `g5-exporters/` | **Deprecated** — use `apps/exporters/` |
| `apple-photos-export/` | Mac Photos → SnapRAID export tooling |
| `media-stack`, `immich` | Symlinks into `apps/` (G5 path compat) |

Never commit `.env`, `secrets/`, app config dirs, Immich library/postgres, or textfile `*.prom`.

## Monitoring stack (Raspberry Pi)

```bash
./deploy-to-pi.sh wmichelin raspberrypi.local
```

- Grafana: http://raspberrypi.local:3000 (Homelab → **Homelab Monitoring**)
- Prometheus targets: http://raspberrypi.local:9090/targets

### G5 exporter notes

- Exporters listen on `192.168.0.54:9100` (node) and `:9633` (SMART).
- SnapRAID / Docker textfile metrics live under `~/code/homelab/apps/exporters/textfile/` (also `~/homelab-exporters/textfile` via symlink).
- Immich UI: http://192.168.0.54:2283 — blackbox probes `/api/server/ping`.

Preferred deploy on G5 is `git pull` in `~/code/homelab`, then `docker compose up -d` in the relevant `apps/*` directory. Helper (rsync fallback):

```bash
./deploy-exporters-to-g5.sh g5 wmichelin
```

## G5 apps

```bash
cd ~/code/homelab/apps/media-stack && docker compose ps
cd ~/code/homelab/apps/immich && docker compose ps
cd ~/code/homelab/apps/exporters && docker compose ps
```

Copy `.env.example` → `.env` on a fresh host (never commit `.env`).

User systemd units:

```bash
~/code/homelab/scripts/install-user-units.sh
```

Shares and storage runbooks: `docs/lan-storage.md`. Config-only backups: `docs/backup-google-drive.md`.

## Apple Photos export (Mac)

See [`apple-photos-export/README.md`](apple-photos-export/README.md).

```bash
cd apple-photos-export
cp config.example.env config.env   # once; gitignored
./export-photos.sh
```
