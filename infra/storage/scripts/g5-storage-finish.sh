#!/bin/bash
set -euo pipefail
log() { echo "[$(date +%H:%M:%S)] $*"; }
USER=wmichelin
UIDN=$(id -u "$USER")
GIDN=$(id -g "$USER")

# Ensure all mounts
mount -a || true
for m in /mnt/disks/disk-ssd1 /mnt/disks/disk-ssd2 /mnt/disks/disk-wd931 /mnt/disks/disk-hgst1 /mnt/disks/disk-hdd22 /mnt/disks/parity1 /mnt/tm/will /mnt/tm/wife /mnt/storage; do
  findmnt "$m" >/dev/null 2>&1 || mount "$m" || true
done

mkdir -p /mnt/storage/{media/{movies,music,tv},torrents/{incomplete,complete},apps}
chown -R "$UIDN:$GIDN" /mnt/storage/media /mnt/storage/torrents /mnt/storage/apps || true
# Don't chown entire mergerfs roots of each disk; just TM + content dirs
chown -R "$UIDN:$GIDN" /mnt/tm/will /mnt/tm/wife
chmod 700 /mnt/tm/will /mnt/tm/wife

mkdir -p /var/snapraid
touch /var/snapraid/content
for d in disk-ssd1 disk-ssd2 disk-wd931 disk-hgst1; do
  mkdir -p "/mnt/disks/$d/.snapraid"
  touch "/mnt/disks/$d/.snapraid/content"
done
mkdir -p /mnt/tm/will/.snapraid /mnt/tm/wife/.snapraid
touch /mnt/tm/will/.snapraid/content /mnt/tm/wife/.snapraid/content

cat > /etc/snapraid.conf <<'EOF'
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

cat > /usr/local/sbin/g5-remount-mergerfs <<'EOF'
#!/bin/bash
set -e
sleep 2
mount -a 2>/dev/null || true
if findmnt /mnt/storage >/dev/null 2>&1; then
  fusermount -uz /mnt/storage 2>/dev/null || umount -l /mnt/storage 2>/dev/null || true
fi
mount /mnt/storage
logger -t g5-storage "mergerfs remounted"
EOF
chmod +x /usr/local/sbin/g5-remount-mergerfs

cat > /etc/udev/rules.d/99-g5-storage-remount.rules <<'EOF'
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

log "Running initial snapraid sync..."
snapraid sync
snapraid status || true

# Samba
SMB_PASS_FILE=/home/wmichelin/.config/lan-remote-password.txt
# Generate samba users - use existing RDP password if present else set placeholder to change
if [[ -f "$SMB_PASS_FILE" ]]; then
  SMBPASS=$(grep '^RDP_PASSWORD=' "$SMB_PASS_FILE" | head -1 | cut -d= -f2-)
else
  SMBPASS=$(openssl rand -base64 12)
fi
WIFEPASS=$(openssl rand -base64 12)

id wife >/dev/null 2>&1 || useradd -m -s /usr/sbin/nologin wife || true
echo -e "$SMBPASS\n$SMBPASS" | smbpasswd -a -s wmichelin
echo -e "$WIFEPASS\n$WIFEPASS" | smbpasswd -a -s wife

# Save wife pass securely
install -d -m 700 -o wmichelin -g wmichelin /home/wmichelin/.config
cat > /home/wmichelin/.config/lan-samba-passwords.txt <<EOF
# Samba credentials for G5 LAN shares
# wmichelin also used for storage + tm-will
SMB_USER_WILL=wmichelin
SMB_PASS_WILL=$SMBPASS
# wife account for tm-wife share
SMB_USER_WIFE=wife
SMB_PASS_WIFE=$WIFEPASS
EOF
chown wmichelin:wmichelin /home/wmichelin/.config/lan-samba-passwords.txt
chmod 600 /home/wmichelin/.config/lan-samba-passwords.txt

cp -a /etc/samba/smb.conf /etc/samba/smb.conf.bak.g5 || true
cat > /etc/samba/smb.conf <<'EOF'
[global]
   workgroup = WORKGROUP
   server string = G5 Storage
   security = user
   map to guest = never
   server role = standalone server
   smb ports = 445
   min protocol = SMB2
   vfs objects = catia fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:nfs_aces = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
   logging = systemd

[storage]
   path = /mnt/storage
   browseable = yes
   read only = no
   valid users = wmichelin
   force user = wmichelin
   force group = wmichelin
   create mask = 0644
   directory mask = 0755

[safe]
   path = /mnt/storage/safe
   browseable = yes
   read only = no
   valid users = wmichelin
   force user = wmichelin
   force group = wmichelin
   create mask = 0644
   directory mask = 0755

[tm-will]
   path = /mnt/tm/will
   browseable = yes
   read only = no
   valid users = wmichelin
   force user = wmichelin
   force group = wmichelin
   vfs objects = catia fruit streams_xattr
   fruit:time machine = yes
   fruit:time machine max size = 0

[tm-wife]
   path = /mnt/tm/wife
   browseable = yes
   read only = no
   valid users = wife
   force user = wife
   force group = wife
   vfs objects = catia fruit streams_xattr
   fruit:time machine = yes
   fruit:time machine max size = 0
EOF

# wife needs write on tm-wife — already owned by wmichelin; fix for wife user
chown -R wife:wife /mnt/tm/wife
chmod 700 /mnt/tm/wife
# snapraid content still needs to be writable by root for sync — ok

systemctl enable --now smbd nmbd
smbcontrol all reload-config || true

# UFW LAN rules
ufw allow from 192.168.0.0/16 to any port 445 proto tcp comment 'Samba LAN' || true
ufw allow from 192.168.0.0/16 to any port 8096 proto tcp comment 'Jellyfin LAN' || true
ufw allow from 192.168.0.0/16 to any port 7878 proto tcp comment 'Radarr LAN' || true
ufw allow from 192.168.0.0/16 to any port 8686 proto tcp comment 'Lidarr LAN' || true
ufw allow from 192.168.0.0/16 to any port 8080 proto tcp comment 'qBittorrent LAN' || true

# Docker group
usermod -aG docker wmichelin || true
systemctl enable --now docker

log "DONE_CONFIG"
df -h /mnt/storage/safe /mnt/storage/media /mnt/tm/will /mnt/tm/wife
snapraid status | head -40
