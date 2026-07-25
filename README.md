# Homelab

Monorepo for home infrastructure: Raspberry Pi monitoring, G5 storage/media stack, exporters, and Mac-side tooling.

**Operate from this Mac.** Remotes are rsync deploy targets — they do not need a git checkout.

## Secrets

Single source of truth (gitignored):

```bash
cp secrets/homelab.env.example secrets/homelab.env
chmod 600 secrets/homelab.env
# edit secrets/homelab.env
./scripts/materialize-env.sh   # writes per-app .env files Docker actually reads
```

Committed template: `secrets/homelab.env.example`. Never commit `secrets/homelab.env` or materialized `.env` files.

## Layout

| Path | Contents |
|------|----------|
| `apps/media-stack/` | Jellyfin, Radarr, Lidarr, qBittorrent, Prowlarr (G5) |
| `apps/immich/` | Immich + ML / CUDA (G5) |
| `apps/exporters/` | node-exporter, SMART, docker/netdev textfile metrics (G5) |
| `infra/` | storage snapshots + systemd unit files |
| `scripts/` | backups, Proton→qBit port sync, env materialize, unit installer |
| `secrets/homelab.env` | unified secrets (local only) |
| `docker-compose.yml`, `grafana/`, `prometheus/`, … | Pi monitoring stack |
| `apple-photos-export/` | Mac Photos → SnapRAID export tooling |

## Deploy (from this host)

Raspberry Pi monitoring:

```bash
./deploy-to-pi.sh            # default SSH host `pi`
./deploy-to-pi.sh pi
```

G5 apps (rsync + compose; no `git pull` on the box):

```bash
./deploy-to-g5.sh            # exporters + media-stack + immich
./deploy-to-g5.sh exporters
./deploy-to-g5.sh media-stack
./deploy-to-g5.sh immich
```

- Grafana: http://raspberrypi.local:3000
- Prometheus: http://raspberrypi.local:9090/targets
- Immich: http://192.168.0.54:2283
- G5 exporters: `:9100` (node), `:9633` (SMART)

## Apple Photos export (Mac)

See [`apple-photos-export/README.md`](apple-photos-export/README.md).
