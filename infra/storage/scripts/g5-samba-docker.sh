#!/bin/bash
set -euo pipefail
USER=wmichelin
UIDN=$(id -u "$USER")
GIDN=$(id -g "$USER")

# Ensure media dirs + ownership
mkdir -p /mnt/storage/{media/{movies,music,tv},torrents/{incomplete,complete},apps}
chown -R "$UIDN:$GIDN" /mnt/storage/media /mnt/storage/torrents /mnt/storage/apps
chown -R "$UIDN:$GIDN" /mnt/tm/will
chmod 700 /mnt/tm/will

# wife user
id wife >/dev/null 2>&1 || useradd -r -m -d /home/wife -s /usr/sbin/nologin wife
chown -R wife:wife /mnt/tm/wife
chmod 700 /mnt/tm/wife
# keep snapraid content owned by root is fine

# Passwords
if [[ -f /home/wmichelin/.config/lan-remote-password.txt ]]; then
  SMBPASS=$(grep '^RDP_PASSWORD=' /home/wmichelin/.config/lan-remote-password.txt | head -1 | cut -d= -f2-)
else
  SMBPASS=$(openssl rand -base64 12)
fi
WIFEPASS=$(openssl rand -base64 12)
echo -e "$SMBPASS\n$SMBPASS" | smbpasswd -a -s wmichelin
echo -e "$WIFEPASS\n$WIFEPASS" | smbpasswd -a -s wife

install -d -m 700 -o wmichelin -g wmichelin /home/wmichelin/.config
cat > /home/wmichelin/.config/lan-samba-passwords.txt <<EOF
# Samba credentials — G5 LAN shares (mode 600)
SMB_USER_WILL=wmichelin
SMB_PASS_WILL=$SMBPASS
SMB_USER_WIFE=wife
SMB_PASS_WIFE=$WIFEPASS
EOF
chown wmichelin:wmichelin /home/wmichelin/.config/lan-samba-passwords.txt
chmod 600 /home/wmichelin/.config/lan-samba-passwords.txt

cp -a /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%s)" || true
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

[tm-wife]
   path = /mnt/tm/wife
   browseable = yes
   read only = no
   valid users = wife
   force user = wife
   force group = wife
   vfs objects = catia fruit streams_xattr
   fruit:time machine = yes
EOF

systemctl enable --now smbd nmbd
smbcontrol all reload-config || systemctl restart smbd

ufw allow from 192.168.0.0/16 to any port 445 proto tcp comment 'Samba LAN' || true
ufw allow from 192.168.0.0/16 to any port 8096 proto tcp comment 'Jellyfin LAN' || true
ufw allow from 192.168.0.0/16 to any port 7878 proto tcp comment 'Radarr LAN' || true
ufw allow from 192.168.0.0/16 to any port 8686 proto tcp comment 'Lidarr LAN' || true
ufw allow from 192.168.0.0/16 to any port 8080 proto tcp comment 'qBittorrent LAN' || true

usermod -aG docker wmichelin
systemctl enable --now docker

echo SAMBA_DOCKER_OK
testparm -s 2>&1 | head -50
