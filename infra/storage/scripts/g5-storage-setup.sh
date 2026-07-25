#!/bin/bash
# G5 storage stack setup — NEVER touches nvme0n1 / the mounted root filesystem.
set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*"; }

assert_not_os() {
  local dev="$1"
  if [[ "$dev" == *nvme* ]]; then
    echo "REFUSING nvme device: $dev" >&2
    exit 99
  fi
  local src
  src=$(findmnt -n -o SOURCE / || true)
  if [[ "$src" == "$dev"* ]]; then
    echo "REFUSING OS root device: $dev (root is $src)" >&2
    exit 99
  fi
  if lsblk -lnpo MOUNTPOINT "$dev" 2>/dev/null | grep -qx /; then
    echo "REFUSING disk with / mounted: $dev" >&2
    exit 99
  fi
}

resolve_disk() {
  local serial="$1" dev
  dev=$(lsblk -ndo NAME,SERIAL | awk -v s="$serial" '$2 == s { print "/dev/" $1; exit }')
  if [[ -z "$dev" ]]; then
    echo "Disk with serial $serial not found" >&2
    exit 1
  fi
  assert_not_os "$dev"
  echo "$dev"
}

wipe_single() {
  local serial="$1" label="$2" dev part
  dev=$(resolve_disk "$serial")
  log "WIPING single disk $label on $dev (serial=$serial)"
  # Unmount children
  while read -r p; do
    [[ -n "$p" ]] || continue
    umount "$p" 2>/dev/null || umount -l "$p" 2>/dev/null || true
  done < <(lsblk -lnpo NAME,TYPE "$dev" | awk '$2=="part"{print $1}')
  wipefs -af "$dev" || true
  sgdisk --zap-all "$dev"
  parted -s "$dev" mklabel gpt
  parted -s "$dev" mkpart "$label" ext4 1MiB 100%
  partprobe "$dev" || true
  sleep 2
  udevadm settle || true
  part=$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2=="part"{print $1; exit}')
  [[ -n "$part" ]] || { echo "No partition on $dev"; exit 1; }
  mkfs.ext4 -F -L "$label" -m 0 -E lazy_itable_init=1,lazy_journal_init=1 "$part"
  log "OK $label -> $part"
}

log "=== Safety: root is $(findmnt -n -o SOURCE /) ==="
[[ "$(findmnt -n -o SOURCE /)" == *nvme* ]] || {
  echo "Unexpected root device; aborting for safety" >&2
  exit 99
}

# Unmount udisks mounts
umount /run/media/wmichelin/* 2>/dev/null || true

# Single disks
wipe_single "WD-WCC6Y0HC973C" "disk-wd931"
wipe_single "2337433E955F" "tm-wife"
wipe_single "201426804192" "disk-ssd1"
wipe_single "323432393830343033343032" "disk-ssd2"
wipe_single "NT3FAHPX" "tm-will"
wipe_single "170412JD10424B0ZZ65S" "disk-hgst1"

# Expansion 22TB: 5TiB parity + rest
EXP=$(resolve_disk "00000000NT17ZN9E")
log "WIPING Expansion $EXP -> parity1 (5TiB) + disk-hdd22"
while read -r p; do
  umount "$p" 2>/dev/null || umount -l "$p" 2>/dev/null || true
done < <(lsblk -lnpo NAME,TYPE "$EXP" | awk '$2=="part"{print $1}')
wipefs -af "$EXP" || true
sgdisk --zap-all "$EXP"
parted -s "$EXP" mklabel gpt
parted -s "$EXP" unit GiB mkpart parity1 ext4 1 5121
parted -s "$EXP" unit GiB mkpart disk-hdd22 ext4 5121 100%
partprobe "$EXP" || true
sleep 3
udevadm settle || true
mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$EXP" | awk '$2=="part"{print $1}')
log "Expansion parts: ${parts[*]}"
[[ ${#parts[@]} -eq 2 ]] || { echo "Expected 2 partitions on Expansion"; exit 1; }
mkfs.ext4 -F -L parity1 -m 0 -E lazy_itable_init=1,lazy_journal_init=1 "${parts[0]}"
mkfs.ext4 -F -L disk-hdd22 -m 0 -E lazy_itable_init=1,lazy_journal_init=1 "${parts[1]}"

log "=== Format complete ==="
lsblk -o NAME,SIZE,FSTYPE,LABEL,SERIAL /dev/sd[a-g] /dev/nvme0n1
log "DONE_FORMAT"
