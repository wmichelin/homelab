#!/bin/bash
# Mounts, fstab, mergerfs, snapraid, samba, docker dirs — never touch nvme root.
set -euo pipefail
log() { echo "[$(date +%H:%M:%S)] $*"; }

[[ "$(findmnt -n -o SOURCE /)" == *nvme* ]] || { echo "Unexpected root"; exit 99; }

uuid_of() { blkid -s UUID -o value "$1"; }
dev_of_label() { blkid -L "$1"; }

mkdir -p /mnt/disks/{disk-ssd1,disk-ssd2,disk-wd931,disk-hgst1,disk-hdd22,parity1}
mkdir -p /mnt/tm/{will,wife}
mkdir -p /mnt/storage/{safe,media,torrents,apps}
mkdir -p /mnt/disks/disk-hdd22/{media/{movies,music,tv},torrents/{incomplete,complete},apps}

# Build fstab entries (idempotent block)
MARKER_BEGIN="# BEGIN G5-STORAGE"
MARKER_END="# END G5-STORAGE"
FSTAB_BLOCK=$(cat <<EOF
$MARKER_BEGIN
# G5 storage stack — mounts by UUID (do not use /dev/sdX)
UUID=$(uuid_of "$(dev_of_label disk-ssd1)")  /mnt/disks/disk-ssd1  ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(uuid_of "$(dev_of_label disk-ssd2)")  /mnt/disks/disk-ssd2  ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(uuid_of "$(dev_of_label disk-wd931)") /mnt/disks/disk-wd931 ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(uuid_of "$(dev_of_label disk-hgst1)") /mnt/disks/disk-hgst1 ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(uuid_of "$(dev_of_label disk-hdd22)") /mnt/disks/disk-hdd22 ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(uuid_of "$(dev_of_label parity1)")    /mnt/disks/parity1    ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(uuid_of "$(dev_of_label tm-will)")    /mnt/tm/will          ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
UUID=$(uuid_of "$(dev_of_label tm-wife)")    /mnt/tm/wife          ext4  defaults,nofail,x-systemd.device-timeout=10,x-systemd.automount  0  2
# SnapRAID-protected pool only (~5TB) — SMB share "safe"
/mnt/disks/disk-ssd1:/mnt/disks/disk-ssd2:/mnt/disks/disk-wd931:/mnt/disks/disk-hgst1  /mnt/storage/safe  fuse.mergerfs  defaults,allow_other,use_ino,category.create=mfs,minfreespace=10G,fsname=mergerfs-safe,nonempty  0  0
# Unprotected bulk (disk-hdd22)
/mnt/disks/disk-hdd22/media     /mnt/storage/media     none  bind,nofail  0  0
/mnt/disks/disk-hdd22/torrents  /mnt/storage/torrents  none  bind,nofail  0  0
/mnt/disks/disk-hdd22/apps      /mnt/storage/apps      none  bind,nofail  0  0
$MARKER_END
EOF
)

cp -a /etc/fstab /etc/fstab.bak.g5-storage.$(date +%Y%m%d%H%M%S)
if grep -q "$MARKER_BEGIN" /etc/fstab; then
  # replace existing block
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' /etc/fstab > /etc/fstab.tmp
  mv /etc/fstab.tmp /etc/fstab
fi
printf '%s\n' "$FSTAB_BLOCK" >> /etc/fstab

log "Mounting disks..."
systemctl daemon-reload
mount -a || true
# Force mount each
for m in /mnt/disks/disk-ssd1 /mnt/disks/disk-ssd2 /mnt/disks/disk-wd931 /mnt/disks/disk-hgst1 /mnt/disks/disk-hdd22 /mnt/disks/parity1 /mnt/tm/will /mnt/tm/wife; do
  mount "$m" 2>/dev/null || mount --target "$m" 2>/dev/null || true
done
# Protected mergerfs + media binds
umount /mnt/storage/safe 2>/dev/null || true
umount /mnt/storage/media /mnt/storage/torrents /mnt/storage/apps 2>/dev/null || true
mount /mnt/storage/safe
mount /mnt/storage/media
mount /mnt/storage/torrents
mount /mnt/storage/apps

log "Mounted:"
findmnt -R /mnt | head -40
df -h /mnt/storage/safe /mnt/storage/media /mnt/tm/will /mnt/tm/wife /mnt/disks/* | sed 's/^/  /'

# Dirs + ownership
USER=wmichelin
UIDN=$(id -u "$USER")
GIDN=$(id -g "$USER")
chown -R "$UIDN:$GIDN" /mnt/disks/disk-hdd22/media /mnt/disks/disk-hdd22/torrents /mnt/disks/disk-hdd22/apps
chown "$UIDN:$GIDN" /mnt/storage /mnt/storage/safe
chown -R "$UIDN:$GIDN" /mnt/tm/will /mnt/tm/wife
chmod 700 /mnt/tm/will /mnt/tm/wife

# SnapRAID content files
mkdir -p /var/snapraid
touch /var/snapraid/content
for d in disk-ssd1 disk-ssd2 disk-wd931 disk-hgst1; do
  mkdir -p "/mnt/disks/$d/.snapraid"
  touch "/mnt/disks/$d/.snapraid/content"
done
mkdir -p /mnt/tm/will/.snapraid /mnt/tm/wife/.snapraid
touch /mnt/tm/will/.snapraid/content /mnt/tm/wife/.snapraid/content
chown -R "$UIDN:$GIDN" /mnt/tm/will/.snapraid /mnt/tm/wife/.snapraid

cat > /etc/snapraid.conf <<'EOF'
# G5 SnapRAID — parity on Expansion; data = pool SSDs/HDDs + TM disks
# disk-hdd22 (bulk media) is intentionally NOT a SnapRAID data disk

parity /mnt/disks/parity1/snapraid.parity

content /var/snapraid/content
content /mnt/disks/disk-ssd1/.snapraid/content
content /mnt/disks/disk-ssd2/.snapraid/content
content /mnt/disks/disk-wd931/.snapraid/content
content /mnt/disks/disk-hgst1/.snapraid/content
content /mnt/tm/will/.snapraid/content
content /mnt/tm/wife/.snapraid/content

data d1 /mnt/disks/disk-ssd1
data d2 /mnt/disks/disk-ssd2
data d3 /mnt/disks/disk-wd931
data d4 /mnt/disks/disk-hgst1
data tmwill /mnt/tm/will
data tmwife /mnt/tm/wife

exclude *.unrecoverable
exclude /tmp/
exclude /lost+found/
exclude .SnapRAID
exclude .snapraid/
exclude .Trash-*/
exclude .Trash/
EOF

# mergerfs remount helper
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

cat > /etc/udev/rules.d/99-g5-storage-remount.rules <<'EOF'
# When a labeled storage disk appears, remount mergerfs after delay
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="disk-ssd1|disk-ssd2|disk-wd931|disk-hgst1|disk-hdd22", RUN+="/bin/systemctl start g5-remount-mergerfs.service"
EOF

cat > /etc/systemd/system/g5-remount-mergerfs.service <<'EOF'
[Unit]
Description=Remount G5 mergerfs after disk hotplug
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/g5-remount-mergerfs
EOF

# SnapRAID timers
cat > /etc/systemd/system/snapraid-sync.service <<'EOF'
[Unit]
Description=SnapRAID sync
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/snapraid sync
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

cat > /etc/systemd/system/snapraid-sync.timer <<'EOF'
[Unit]
Description=Nightly SnapRAID sync

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/snapraid-scrub.service <<'EOF'
[Unit]
Description=SnapRAID scrub
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/snapraid scrub -p 100 -o 30
Nice=10
EOF

cat > /etc/systemd/system/snapraid-scrub.timer <<'EOF'
[Unit]
Description=Weekly SnapRAID scrub

[Timer]
OnCalendar=Sun *-*-* 05:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now snapraid-sync.timer snapraid-scrub.timer
udevadm control --reload

log "Initial snapraid sync (may take a while on empty disks — quick)..."
snapraid sync || true
snapraid status || true

log "DONE_MOUNTS"
