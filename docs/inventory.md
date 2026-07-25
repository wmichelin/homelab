# Inventory

Where things run and how they are deployed. Operate from the Mac; remotes are rsync targets.

| Host | Role | Remote path | Deploy |
|------|------|-------------|--------|
| Mac | Source of truth (git + `secrets/homelab.env`) | `~/code/homelab` | — |
| Pi (`pi` / raspberrypi.local) | Prometheus, Grafana, local exporters, Hubitat, Pantry | `~/homelab` | `./deploy-to-pi.sh` |
| G5 (`g5` / 192.168.0.54) | Media, Immich, exporters, SnapRAID/Samba | `~/code/homelab` | `./deploy-to-g5.sh` |

## Pi

| Component | Location |
|-----------|----------|
| Compose | `docker-compose.yml` |
| Systemd | `systemd/homelab-stack.service`, `homelab-watchdog.{service,timer}` (installed by deploy) |
| Secrets | Materialized root `.env` (monitoring keys only) |
| Scrapes G5 | `prometheus/prometheus.yml` → `:9100`, `:9633`, blackbox |

## G5

| Component | Location |
|-----------|----------|
| Media stack | `apps/media-stack/` (+ `config/` runtime, rsync-excluded) |
| Immich | `apps/immich/` (`library/`, `postgres/` rsync-excluded) |
| Exporters | `apps/exporters/` (`textfile/*.prom` rsync-excluded) |
| User units | `infra/systemd/user/` via `scripts/install-user-units.sh` |
| System units / `/usr/local` | `scripts/install-g5-system.sh` or `./deploy-to-g5.sh --system` |
| Host config snapshots | `infra/storage/` (fstab / snapraid / smb — apply manually) |
| Compat symlinks | `~/networked-storage` → repo; `~/homelab-exporters` → `apps/exporters` |

## Secrets

Single file: `secrets/homelab.env`. Materialize with `./scripts/materialize-env.sh [--target pi|g5|all]`.
