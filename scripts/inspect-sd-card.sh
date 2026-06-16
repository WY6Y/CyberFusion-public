#!/bin/bash
# Read-only check of Pi Zero SD card WiFi state. No changes.
# Usage: sudo bash inspect-sd-card.sh /path/to/mounted/root
set -euo pipefail
ROOT="${1:?Usage: sudo $0 /path/to/mounted/root}"
NM_DIR="$ROOT/etc/NetworkManager/system-connections"

echo "=== SD card inspection: $ROOT ==="
echo ""

echo "--- NetworkManager profiles ---"
if [[ -d "$NM_DIR" ]]; then
  ls -la "$NM_DIR"
  echo ""
  for f in "$NM_DIR"/*; do
    [[ -f "$f" ]] || continue
    echo ">> $(basename "$f")"
    grep -E '^(id|ssid|autoconnect|autoconnect-priority|psk=)' "$f" 2>/dev/null | sed 's/psk=.*/psk=***hidden***/' || true
    echo ""
  done
else
  echo "(no $NM_DIR)"
fi

echo "--- hostapd ---"
if [[ -f "$ROOT/etc/hostapd/hostapd.conf" ]]; then
  grep -E '^(ssid|wpa_passphrase|wpa=)' "$ROOT/etc/hostapd/hostapd.conf"
else
  echo "(no hostapd.conf)"
fi

echo ""
echo "--- wifi-fallback boot ---"
if [[ -L "$ROOT/etc/systemd/system/multi-user.target.wants/cyberfusion-wifi-fallback.service" ]]; then
  echo "ENABLED at boot"
else
  echo "DISABLED at boot"
fi

echo ""
echo "--- SSH on boot ---"
[[ -f "$ROOT/boot/firmware/ssh" || -f "$ROOT/boot/ssh" ]] && echo "ssh file present" || echo "ssh file MISSING"