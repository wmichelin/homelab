#!/bin/bash
# Rename tm-will -> tm-walter (mount, label, samba, snapraid). Never touch nvme.
set -euo pipefail

[[ "$(findmnt -n -o SOURCE /)" == *nvme* ]] || exit 99

# Unmount old path
systemctl stop mnt-tm-will.automount mnt-tm-will.mount 2>/dev/null || true
umount /mnt/tm/will 2>/dev/null || umount -l /mnt/tm/will 2>/dev/null || true

# Relabel filesystem
DEV=$(blkid -L tm-will || true)
if [[ -z "$DEV" ]]; then
  DEV=$(blkid -L tm-walter || true)
fi
[[ -n "$DEV" ]] || { echo "tm-will/tm-walter device not found"; exit 1; }
e2label "$DEV" tm-walter

mkdir -p /mnt/tm/walter

# Update fstab
sed -i 's|/mnt/tm/will|/mnt/tm/walter|g' /etc/fstab

# Update snapraid
sed -i 's|/mnt/tm/will|/mnt/tm/walter|g' /etc/snapraid.conf
sed -i 's|data tmwill|data tmwalter|g' /etc/snapraid.conf

# Update samba
sed -i 's|\[tm-will\]|[tm-walter]|g' /etc/samba/smb.conf
sed -i 's|/mnt/tm/will|/mnt/tm/walter|g' /etc/samba/smb.conf

# Remove empty old mount dir if present
rmdir /mnt/tm/will 2>/dev/null || true

systemctl daemon-reload
mount /mnt/tm/walter
chown -R wmichelin:wmichelin /mnt/tm/walter
chmod 700 /mnt/tm/walter

systemctl restart smbd nmbd || true
# Refresh snapraid content paths (sync is cheap if empty-ish)
snapraid sync || true

echo "LABEL=$(e2label "$DEV")"
findmnt /mnt/tm/walter
grep -E 'tm-walter|tmwalter' /etc/fstab /etc/samba/smb.conf /etc/snapraid.conf
echo RENAME_OK
