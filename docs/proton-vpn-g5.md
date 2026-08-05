# Proton VPN on G5

G5 runs **Proton VPN CLI** (WireGuard) so torrent traffic egresses via VPN + port forwarding. qBittorrent port sync: `scripts/proton-qbit-port-forward.sh` (user unit `proton-qbit-port-forward.service`).

Helper: `scripts/proton-vpn-fix.sh` · Polkit rule: `infra/polkit/49-nm-proton-wmichelin.rules`

## One-time setup (SSH / headless)

Proton’s CLI always creates a temporary NetworkManager kill-switch while connecting. Over SSH there is no GUI polkit agent, so NM returns **Insufficient privileges** unless you allow it:

```bash
cd ~/code/homelab
./scripts/proton-vpn-fix.sh install-polkit   # sudo password once
./scripts/proton-vpn-fix.sh check-polkit     # expect: yes / yes
```

Then:

```bash
protonvpn signin          # if needed
./scripts/proton-vpn-fix.sh connect
# or: protonvpn connect --country US
```

## Day-to-day

| Task | Command |
|------|---------|
| Status + public IP | `./scripts/proton-vpn-fix.sh status` |
| Connect (US) | `./scripts/proton-vpn-fix.sh connect` |
| Disconnect | `./scripts/proton-vpn-fix.sh disconnect` |
| Full recover | `./scripts/proton-vpn-fix.sh recover` |
| Diagnose | `./scripts/proton-vpn-fix.sh doctor` |

Override country: `PROTON_CONNECT_COUNTRY=NL ./scripts/proton-vpn-fix.sh connect`

Port forwarding for qBit is handled by the user service (NAT-PMP to `10.2.0.1`). After a reconnect, if the listen port looks wrong:

```bash
systemctl --user restart proton-qbit-port-forward.service
journalctl --user -u proton-qbit-port-forward.service -n 30 --no-pager
```

## qBittorrent kill switch

qBittorrent uses **host networking** and binds BitTorrent to **`proton0`**.

- Proton up + `proton0` present → peers work; NAT-PMP port synced by `proton-qbit-port-forward.service`
- Proton down / no `proton0` → no torrent peers (WebUI on `:8080` / `qbittorrent.g5.lan` can still work)
- Caddy proxies to `host.docker.internal:8080` (not the old compose DNS name `qbittorrent`)
- Radarr/Sonarr/Lidarr download client host must be `host.docker.internal` (or `192.168.0.54`), port `8080`

### Docker → WebUI (one-time)

Proton’s kill-switch often blocks container → host `:8080` (docker-proxy ports like `:9100` are unaffected). Allow Docker bridges once:

```bash
sudo ~/code/homelab/scripts/g5-allow-docker-qbit-webui.sh
```

Then verify:

```bash
docker exec radarr curl -fsS -m 3 -o /dev/null -w '%{http_code}\n' http://172.18.0.1:8080/
```

## When Prowlarr / indexers “go down”

Usually **not** Prowlarr itself — the container stays up, but **egress through a dead Proton tunnel** fails (kill switch still on). Symptoms:

- `https://prowlarr.g5.lan` works
- Logs: `Cardigann: Unable to connect to indexer` / SSL `unexpected eof`
- Host: `curl https://www.google.com` times out or TLS EOF while `protonvpn status` still says Connected
- Log: `ExpiredCertificate` in `~/.cache/Proton/VPN/logs/vpn-cli.log`

**Fix:**

```bash
./scripts/proton-vpn-fix.sh doctor    # confirm
./scripts/proton-vpn-fix.sh recover   # clean stale NM + reconnect
```

Manual equivalent if the helper is unavailable:

```bash
nmcli -t -f NAME connection show | grep -iE 'ProtonVPN|pvpn-' | while read -r n; do
  sudo nmcli connection delete "$n"
done
protonvpn connect --country US
protonvpn status
curl -s https://ipinfo.io
```

## Why CLI said “unexpected error”

Friendly message hides the real exception. Common ones on G5:

| Real error | Cause | Fix |
|------------|--------|-----|
| `Insufficient privileges` adding/removing KS | No polkit for SSH user | `install-polkit` |
| `ExpiredCertificate` | WireGuard cert expired; tunnel zombie | `recover` |
| Stuck `pvpn-killswitch-*` after failed disconnect | NM leftovers | `recover` / `sudo nmcli connection delete …` |

To print the real traceback:

```bash
python3 - <<'PY'
from proton.vpn.cli import main
main(cli_args=["--verbose", "connect", "--country", "US"])
PY
```

## Related

- Media stack / qBittorrent: [`docs/lan-storage.md`](lan-storage.md)
- Inventory: [`docs/inventory.md`](inventory.md)
