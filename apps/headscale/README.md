# Headscale (control plane)

Runs on the **pantry DigitalOcean droplet** as a separate container (`127.0.0.1:8081`), not on G5.

- Config: `config.yaml`, `extra-records.json`
- Deploy: `../../scripts/deploy-headscale-to-droplet.sh`
- DNS A record: `../../terraform/headscale/`
- Full runbook: [`docs/headscale-tailscale.md`](../../docs/headscale-tailscale.md)
