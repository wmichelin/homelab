#!/bin/bash
# Split /mnt/storage: SnapRAID pool → /mnt/storage/safe; media/torrents/apps stay on disk-hdd22.
# Never touches NVMe root filesystem contents beyond the /mnt/storage glue dir.
set -euo pipefail
log() { echo "[$(date +%H:%M:%S)] $*"; }

[[ "$(findmnt -n -o SOURCE /)" == *nvme* ]] || { echo "Unexpected root"; exit 99; }

USER=wmichelin
UIDN=$(id -u "$USER")
GIDN=$(id -g "$USER")
COMPOSE=/home/wmichelin/code/homelab/apps/media-stack/docker-compose.yml

log "Stopping media stack (if running)..."
if [[ -f "$COMPOSE" ]]; then
  docker compose -f "$COMPOSE" stop 2>/dev/null || true
fi

log "Backing up fstab + smb.conf..."
cp -a /etc/fstab "/etc/fstab.bak.split.$(date +%Y%m%d%H%M%S)"
cp -a /etc/samba/smb.conf "/etc/samba/smb.conf.bak.split.$(date +%Y%m%d%H%M%S)"

log "Unmounting old mergerfs at /mnt/storage..."
# May be stacked; peel until gone
for _ in 1 2 3 4 5; do
  findmnt /mnt/storage >/dev/null 2>&1 || break
  fusermount -uz /mnt/storage 2>/dev/null || umount -l /mnt/storage 2>/dev/null || true
  sleep 0.5
done
if findmnt /mnt/storage >/dev/null 2>&1; then
  echo "ERROR: could not unmount /mnt/storage"; findmnt -R /mnt/storage; exit 1
fi

# Ensure branch disks are mounted
for m in /mnt/disks/disk-ssd1 /mnt/disks/disk-ssd2 /mnt/disks/disk-wd931 /mnt/disks/disk-hgst1 /mnt/disks/disk-hdd22; do
  findmnt "$m" >/dev/null 2>&1 || mount "$m" || true
done

# Media already lives only on disk-hdd22 — ensure dirs exist there
mkdir -p /mnt/disks/disk-hdd22/{media/{movies,music,tv},torrents/{incomplete,complete},apps}
chown -R "$UIDN:$GIDN" /mnt/disks/disk-hdd22/media /mnt/disks/disk-hdd22/torrents /mnt/disks/disk-hdd22/apps

# Glue directory on root NVMe
mkdir -p /mnt/storage/{safe,media,torrents,apps}

MARKER_BEGIN="# BEGIN G5-STORAGE"
MARKER_END="# END G5-STORAGE"
FSTAB_BLOCK=$(cat <<EOF
$MARKER_BEGIN
# G5 storage stack — mounts by UUID (do not use /dev/sdX)
UUID=$(blkid -s UUID -o value "$(blkid -L disk-ssd1)")  /mnt/disks/disk-ssd1  ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(blkid -s UUID -o value "$(blkid -L disk-ssd2)")  /mnt/disks/disk-ssd2  ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(blkid -s UUID -o value "$(blkid -L disk-wd931)") /mnt/disks/disk-wd931 ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(blkid -s UUID -o value "$(blkid -L disk-hgst1)") /mnt/disks/disk-hgst1 ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(blkid -s UUID -o value "$(blkid -L disk-hdd22)") /mnt/disks/disk-hdd22 ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(blkid -s UUID -o value "$(blkid -L parity1)")    /mnt/disks/parity1    ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(blkid -s UUID -o value "$(blkid -L tm-walter)")  /mnt/tm/walter        ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(blkid -s UUID -o value "$(blkid -L tm-marissa)") /mnt/tm/marissa       ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
# SnapRAID-protected pool only (~5TB) — SMB share "safe"
/mnt/disks/disk-ssd1:/mnt/disks/disk-ssd2:/mnt/disks/disk-wd931:/mnt/disks/disk-hgst1  /mnt/storage/safe  fuse.mergerfs  defaults,allow_other,use_ino,category.create=mfs,minfreespace=10G,fsname=mergerfs-safe,nonempty  0  0
# Unprotected bulk (disk-hdd22) — media / torrents / apps
/mnt/disks/disk-hdd22/media     /mnt/storage/media     none  bind,nofail  0  0
/mnt/disks/disk-hdd22/torrents  /mnt/storage/torrents  none  bind,nofail  0  0
/mnt/disks/disk-hdd22/apps      /mnt/storage/apps      none  bind,nofail  0  0
$MARKER_END
EOF
)

awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  !skip {print}
' /etc/fstab > /etc/fstab.tmp
mv /etc/fstab.tmp /etc/fstab
printf '%s\n' "$FSTAB_BLOCK" >> /etc/fstab

log "Mounting new layout..."
systemctl daemon-reload
mount /mnt/storage/safe
mount /mnt/storage/media
mount /mnt/storage/torrents
mount /mnt/storage/apps

chown "$UIDN:$GIDN" /mnt/storage /mnt/storage/safe
chmod 755 /mnt/storage /mnt/storage/safe

# Remount helper
cat > /usr/local/sbin/g5-remount-mergerfs <<'EOF'
#!/bin/bash
# Remount protected mergerfs + media binds after a branch disk returns
set -e
sleep 2
mount -a 2>/dev/null || true
for m in /mnt/disks/disk-ssd1 /mnt/disks/disk-ssd2 /mnt/disks/disk-wd931 /mnt/disks/disk-hgst1 /mnt/disks/disk-hdd22; do
  findmnt "$m" >/dev/null 2>&1 || mount "$m" 2>/dev/null || true
done
if findmnt /mnt/storage/safe >/dev/null 2>&1; then
  fusermount -uz /mnt/storage/safe 2>/dev/null || umount -l /mnt/storage/safe 2>/dev/null || true
fi
mount /mnt/storage/safe 2>/dev/null || true
for b in media torrents apps; do
  findmnt "/mnt/storage/$b" >/dev/null 2>&1 || mount "/mnt/storage/$b" 2>/dev/null || true
done
logger -t g5-storage "mergerfs-safe + binds remounted"
EOF
chmod +x /usr/local/sbin/g5-remount-mergerfs

# Samba: add [safe], keep [storage] as the glue tree
python3 - <<'PY'
from pathlib import Path
p = Path("/etc/samba/smb.conf")
text = p.read_text()
if "[safe]" not in text:
    block = """
[safe]
   path = /mnt/storage/safe
   browseable = yes
   read only = no
   valid users = wmichelin
   force user = wmichelin
   force group = wmichelin
   create mask = 0644
   directory mask = 0755
"""
    # Insert after [storage] section — before first [tm-
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    inserted = False
    while i < len(lines):
        out.append(lines[i])
        if not inserted and lines[i].strip() == "[storage]":
            i += 1
            while i < len(lines) and not lines[i].startswith("["):
                out.append(lines[i])
                i += 1
            out.append(block if block.endswith("\n") else block + "\n")
            inserted = True
            continue
        i += 1
    if not inserted:
        out.append(block)
    p.write_text("".join(out))
print("smb.conf updated")
PY

smbcontrol all reload-config || systemctl restart smbd

log "Starting media stack..."
if [[ -f "$COMPOSE" ]]; then
  docker compose -f "$COMPOSE" start 2>/dev/null || docker compose -f "$COMPOSE" up -d || true
fi

log "Verify:"
findmnt -R /mnt/storage || true
df -h /mnt/storage/safe /mnt/storage/media /mnt/disks/disk-hdd22 | sed 's/^/  /'
testparm -s 2>/dev/null | grep -E '^\[|path =' | sed 's/^/  /'
ls -la /mnt/storage | sed 's/^/  /'
log "DONE_SPLIT"
