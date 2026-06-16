#!/bin/bash
# Fix MMDVM serial port (required for RF + parrot echo).
# Run on Pi Zero: sudo bash fix-modem.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run: sudo bash $0"; exit 1; }

BOOT="/boot/firmware"
[[ -d "$BOOT" ]] || BOOT="/boot"

echo "=== Fix MMDVM serial (/dev/serial0) ==="

# Serial console steals the UART from the MMDVM hat
if [[ -f "$BOOT/cmdline.txt" ]]; then
  sed -i 's/console=serial0,[0-9]* //g; s/console=ttyAMA0,[0-9]* //g; s/console=ttyS0,[0-9]* //g' "$BOOT/cmdline.txt"
  echo "[ok] removed serial console from cmdline.txt"
fi

systemctl disable --now serial-getty@ttyS0.service 2>/dev/null || true
systemctl mask serial-getty@ttyS0.service 2>/dev/null || true
echo "[ok] disabled serial-getty on ttyS0"

cat >/etc/udev/rules.d/99-mmdvm-serial.rules <<'EOF'
SUBSYSTEM=="tty", KERNEL=="ttyAMA0|ttyS0", GROUP="dialout", MODE="0660"
EOF
udevadm control --reload-rules
udevadm trigger
sleep 1
if [[ -e /dev/ttyS0 ]]; then
  chgrp dialout /dev/ttyS0
  chmod 660 /dev/ttyS0
fi
echo "[ok] $(ls -la /dev/ttyS0 /dev/serial0 2>/dev/null)"

systemctl kill -s KILL mmdvmhost 2>/dev/null || true
sleep 2
systemctl reset-failed mmdvmhost 2>/dev/null || true
systemctl start mmdvmhost
sleep 3

if systemctl is-active --quiet mmdvmhost; then
  CPU=$(ps -o pcpu= -p "$(pgrep -x MMDVMHost)" 2>/dev/null | tr -d ' ' || echo "?")
  echo "[ok] mmdvmhost active (CPU ${CPU}%)"
else
  echo "[FAIL] mmdvmhost not running — check: journalctl -u mmdvmhost -n 20"
  exit 1
fi

if [[ -x /usr/local/bin/ysf-link ]]; then
  /usr/local/bin/ysf-link "ZZ Parrot"
  echo "[ok] linked to ZZ Parrot"
fi

echo ""
echo "PTT on your simplex frequency for 3+ seconds, wait for echo."
echo "Reboot once when convenient so cmdline.txt change sticks cleanly."