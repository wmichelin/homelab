#!/bin/bash
# Rename tm-wife -> tm-marissa; Linux user wife -> marissa. Never touch nvme.
set -euo pipefail

[[ "$(findmnt -n -o SOURCE /)" == *nvme* ]] || exit 99

systemctl stop mnt-tm-wife.automount mnt-tm-wife.mount 2>/dev/null || true
umount /mnt/tm/wife 2>/dev/null || umount -l /mnt/tm/wife 2>/dev/null || true

DEV=$(blkid -L tm-wife || blkid -L tm-marissa || true)
[[ -n "$DEV" ]] || { echo "tm-wife device not found"; exit 1; }
e2label "$DEV" tm-marissa

mkdir -p /mnt/tm/marissa

sed -i 's|/mnt/tm/wife|/mnt/tm/marissa|g' /etc/fstab
sed -i 's|/mnt/tm/wife|/mnt/tm/marissa|g' /etc/snapraid.conf
sed -i 's|data tmwife|data tmmarissa|g' /etc/snapraid.conf

# Samba share + user references
sed -i 's|\[tm-wife\]|[tm-marissa]|g' /etc/samba/smb.conf
sed -i 's|/mnt/tm/wife|/mnt/tm/marissa|g' /etc/samba/smb.conf
sed -i 's|valid users = wife|valid users = marissa|g' /etc/samba/smb.conf
sed -i 's|force user = wife|force user = marissa|g' /etc/samba/smb.conf
sed -i 's|force group = wife|force group = marissa|g' /etc/samba/smb.conf

# Rename Linux user if present
if id wife >/dev/null 2>&1; then
  if id marissa >/dev/null 2>&1; then
    echo "marissa user already exists; removing old wife after migrating smb"
  else
    # kill any processes
    pkill -u wife 2>/dev/null || true
    usermod -l marissa wife
    groupmod -n marissa wife 2>/dev/null || true
    usermod -d /home/marissa -m marissa 2>/dev/null || true
  fi
fi
id marissa >/dev/null 2>&1 || useradd -r -m -d /home/marissa -s /usr/sbin/nologin marissa

# Migrate samba password: copy from wife to marissa if needed
if pdbedit -L 2>/dev/null | grep -q '^wife:'; then
  # re-add marissa with same password from secrets file if available
  PASSFILE=/home/wmichelin/code/homelab/secrets/homelab.env
  if [[ -f "$PASSFILE" ]]; then
    WPASS=$(grep -E '^SMB_PASS_(WIFE|MARISSA)=' "$PASSFILE" | head -1 | cut -d= -f2-)
  else
    WPASS=$(openssl rand -base64 12)
  fi
  echo -e "$WPASS\n$WPASS" | smbpasswd -a -s marissa
  smbpasswd -x wife 2>/dev/null || true
fi
# Ensure marissa has smb account
if ! pdbedit -L 2>/dev/null | grep -q '^marissa:'; then
  PASSFILE=/home/wmichelin/code/homelab/secrets/homelab.env
  WPASS=$(grep -E '^SMB_PASS_(WIFE|MARISSA)=' "$PASSFILE" 2>/dev/null | head -1 | cut -d= -f2-)
  [[ -n "$WPASS" ]] || WPASS=$(openssl rand -base64 12)
  echo -e "$WPASS\n$WPASS" | smbpasswd -a -s marissa
fi

rmdir /mnt/tm/wife 2>/dev/null || true

systemctl daemon-reload
mount /mnt/tm/marissa
chown -R marissa:marissa /mnt/tm/marissa
chmod 700 /mnt/tm/marissa

systemctl restart smbd nmbd || true
snapraid sync || true

echo "LABEL=$(e2label "$DEV")"
findmnt /mnt/tm/marissa
id marissa
grep -E 'tm-marissa|marissa|tmwife|wife' /etc/fstab /etc/samba/smb.conf /etc/snapraid.conf || true
echo RENAME_OK
