# Infrastructure (host)

Checked-in copies of host config that lives under `/etc` and `/usr/local`.  
Edit here, then apply with the install helpers below. This repo does **not** auto-write `/etc/fstab`, `/etc/snapraid.conf`, or `/etc/samba/smb.conf`.

| Repo path | Live path |
|-----------|-----------|
| `storage/fstab.g5-storage` | `/etc/fstab` (G5-STORAGE block) — manual |
| `storage/snapraid.conf` | `/etc/snapraid.conf` — manual |
| `storage/smb.conf` | `/etc/samba/smb.conf` — manual |
| `storage/g5-remount-mergerfs` | `/usr/local/sbin/g5-remount-mergerfs` |
| `systemd/system/*` | `/etc/systemd/system/` |
| `systemd/user/*` | via `scripts/install-user-units.sh` |
| `storage/scripts/archive/` | one-shot history — do not re-run blindly |

## Install on G5

User units (no sudo):

```bash
~/code/homelab/scripts/install-user-units.sh
# or: ./deploy-to-g5.sh exporters
```

System scripts + units (sudo on the G5 console — passwordless sudo is not configured):

```bash
sudo ~/code/homelab/scripts/install-g5-system.sh
# or from Mac once passwordless/TTY sudo works: ./deploy-to-g5.sh --system
```

Until that runs, live `/etc/systemd/system/snapraid-*.service` may still call bare `/usr/bin/snapraid` (works; job textfile metrics come from the user `snapraid-metrics.timer` path).
