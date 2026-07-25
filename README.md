# Homelab

Monorepo for home infrastructure: Raspberry Pi monitoring, G5 storage/media stack, exporters, and Mac-side tooling.

**Operate from this Mac.** Remotes are rsync deploy targets — they do not need a git checkout.

See [`docs/inventory.md`](docs/inventory.md) for host → path → unit mapping.

## Secrets

```bash
cp secrets/homelab.env.example secrets/homelab.env
chmod 600 secrets/homelab.env
# edit secrets/homelab.env
./scripts/materialize-env.sh   # or --target pi|g5
```

Never commit `secrets/homelab.env` or materialized `.env` files.

## Layout

| Path | Contents |
|------|----------|
| `apps/media-stack/` | Jellyfin, Radarr, Lidarr, qBittorrent, Prowlarr (G5) |
| `apps/immich/` | Immich + ML / CUDA (G5) |
| `apps/exporters/` | node-exporter, SMART, docker/netdev textfile metrics (G5) |
| `infra/systemd/` | G5 system + user unit files (sole unit source) |
| `infra/storage/` | fstab/SnapRAID/Samba snapshots + archived setup scripts |
| `scripts/` | deploys helpers, backups, Proton→qBit, materialize-env |
| `secrets/homelab.env` | unified secrets (local only) |
| `docker-compose.yml`, `grafana/`, `prometheus/`, `systemd/` | Pi monitoring stack |
| `apple-photos-export/` | Mac Photos → SnapRAID export tooling |

## Deploy (from this host)

```bash
./deploy-to-pi.sh                 # Pi monitoring + systemd units
./deploy-to-g5.sh                 # exporters + media-stack + immich
./deploy-to-g5.sh exporters
./deploy-to-g5.sh --system        # also install /usr/local + system units (sudo on G5)
```

- Grafana: http://raspberrypi.local:3000
- Immich: http://192.168.0.54:2283
- G5 exporters: `:9100` (node), `:9633` (SMART)

## Apple Photos export (Mac)

See [`apple-photos-export/README.md`](apple-photos-export/README.md).
