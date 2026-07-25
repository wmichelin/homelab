# Infrastructure (host)

Checked-in copies of host config that lives under `/etc` and `/usr/local`.  
Edit here, then apply with sudo (this repo does not auto-write system files).

| Repo path | Live path |
|-----------|-----------|
| `storage/fstab.g5-storage` | `/etc/fstab` (G5-STORAGE block) |
| `storage/snapraid.conf` | `/etc/snapraid.conf` |
| `storage/smb.conf` | `/etc/samba/smb.conf` |
| `storage/g5-remount-mergerfs` | `/usr/local/sbin/g5-remount-mergerfs` |
| `systemd/system/*` | `/etc/systemd/system/` |
| `systemd/user/*` | installed via `~/code/homelab/scripts/install-user-units.sh` |
| `storage/scripts/` | one-shot array build / migration helpers |

User units:

```bash
~/code/homelab/scripts/install-user-units.sh
```
