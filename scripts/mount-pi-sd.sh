#!/bin/bash
# Helper: find and mount Pi Zero SD card on Grok build host.
# Usage: sudo bash mount-pi-sd.sh
set -euo pipefail

MOUNT_ROOT="${MOUNT_ROOT:-/mnt/sdroot}"
MOUNT_BOOT="${MOUNT_BOOT:-/mnt/sdboot}"

pick_sd() {
  lsblk -dpno NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | awk '
    $3=="disk" && $1 !~ /mmcblk0/ && ($4=="usb" || $1 ~ /mmcblk[1-9]/ || $1 ~ /^sd/) { print $1, $2, $5 }
  '
}

echo "Looking for removable SD (not the main mmcblk0 system disk)..."
mapfile -t candidates < <(pick_sd)

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "No SD card found. Insert the Pi Zero SD card and run again."
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
  exit 1
fi

echo "Candidates:"
printf '  %s\n' "${candidates[@]}"

DISK="$(echo "${candidates[0]}" | awk '{print $1}')"
echo "Using: $DISK"

mkdir -p "$MOUNT_ROOT" "$MOUNT_BOOT"

# Root is usually partition 2, boot partition 1 on modern Pi OS
ROOT_PART="${DISK}p2"
BOOT_PART="${DISK}p1"
[[ -b "$ROOT_PART" ]] || ROOT_PART="${DISK}2"
[[ -b "$BOOT_PART" ]] || BOOT_PART="${DISK}1"

mountpoint -q "$MOUNT_ROOT" || mount "$ROOT_PART" "$MOUNT_ROOT"
mountpoint -q "$MOUNT_BOOT" || mount "$BOOT_PART" "$MOUNT_BOOT"

echo ""
echo "Mounted:"
findmnt "$MOUNT_ROOT" "$MOUNT_BOOT"
echo ""
echo "Run fix:"
echo "  sudo bash ~/cyberfusion-pi-zero/scripts/fix-sd-card.sh $MOUNT_ROOT"