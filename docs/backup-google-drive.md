# Offsite backup (Google Drive)

What gets backed up: docs, scripts, secrets, `docker-compose.yml`, and media-stack app configs.  
What does **not**: `/mnt/storage` media library, TM disk contents, SnapRAID parity.

## Status

- rclone remote **`gdrive`** is configured.
- Folder on Drive: **G5-networked-storage/** (legacy name)
- Weekly automatic upload: user timer `g5-backup-gdrive.timer` (Sundays ~06:30).

## Local only

```bash
~/code/homelab/scripts/backup-to-archive.sh
```

Archives land in `~/code/homelab/backups/` (mode 600; keeps last 10).

Encrypted local archive:

```bash
~/code/homelab/scripts/backup-to-archive.sh --encrypt
```

## Manual Google Drive upload

```bash
~/code/homelab/scripts/backup-to-gdrive.sh
```

## Timer

```bash
systemctl --user status g5-backup-gdrive.timer
systemctl --user start g5-backup-gdrive.service   # run now
```
