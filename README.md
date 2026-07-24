# Homelab Monitoring Stack

## Deployment

Deploy monitoring stack to Raspberry Pi:
```bash
./deploy-to-pi.sh wmichelin raspberrypi.local
```

Deploy exporters to G5 (node-exporter, smartctl-exporter, SnapRAID + Docker textfile metrics):
```bash
./deploy-exporters-to-g5.sh g5 wmichelin
```

## Access

- Grafana: http://raspberrypi.local:3000 (Homelab → **Homelab Monitoring**)
- Prometheus targets: http://raspberrypi.local:9090/targets

## G5 notes

- Exporters listen on `192.168.0.54:9100` (node) and `:9633` (SMART).
- SnapRAID status/job metrics and Docker CPU/mem are written under `~/homelab-exporters/textfile/` by user systemd timers.
- If `snapraid_status_ok` is 0, check `snapraid status` on g5 (currently fails if a configured content dir is missing, e.g. `/mnt/tm/marissa/.snapraid/`).
