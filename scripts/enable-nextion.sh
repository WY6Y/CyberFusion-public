#!/bin/bash
# Enable Nextion on AURSINC v1.5.2 hat (4-pin header, Pi-Star style).
# Run on Pi Zero: sudo bash enable-nextion.sh
set -euo pipefail
CONF=/etc/mmdvmhost
[[ $EUID -eq 0 ]] || { echo "Run with: sudo bash $0"; exit 1; }

echo "=== Enable CyberFusion Nextion ==="

# Hat-routed display: transparent serial through MMDVM firmware (same as Pi-Star "Modem").
grep -q '^\[Transparent Data\]' "$CONF" || echo -e "\n[Transparent Data]" >> "$CONF"
sed -i '/^\[Transparent Data\]/,/^\[/ s/^Enable=.*/Enable=1/' "$CONF"
grep -q '^SendFrameType=' "$CONF" || sed -i '/^\[Transparent Data\]/a SendFrameType=1' "$CONF"
sed -i '/^\[Transparent Data\]/,/^\[/ s/^SendFrameType=.*/SendFrameType=1/' "$CONF"

sed -i 's/^Display=.*/Display=Nextion/' "$CONF"

grep -q '^\[Nextion\]' "$CONF" || cat >>"$CONF" <<'EOF'

[Nextion]
Display=1
Port=/dev/ttyUSB0
Brightness=50
DisplayClock=1
UTC=0
ScreenLayout=0
IdleBrightness=20
EOF

sed -i '/^\[Nextion\]/,/^\[/ s/^Display=.*/Display=1/' "$CONF"
sed -i '/^\[Nextion\]/,/^\[/ s/^ScreenLayout=.*/ScreenLayout=0/' "$CONF"
sed -i '/^\[Nextion\]/,/^\[/ s/^Brightness=.*/Brightness=50/' "$CONF"
sed -i '/^\[Nextion\]/,/^\[/ s/^DisplayClock=.*/DisplayClock=1/' "$CONF"
sed -i '/^\[Nextion\]/,/^\[/ s/^IdleBrightness=.*/IdleBrightness=20/' "$CONF"

if strings /usr/local/bin/MMDVMHost 2>/dev/null | grep -qi nextion; then
  echo "MMDVMHost: Nextion support detected in binary"
else
  echo "WARNING: MMDVMHost binary may lack Nextion driver."
  echo "  Rebuild from https://github.com/g4klx/MMDVM-Host with Display-Driver"
  echo "  or run: bash ~/cyberfusion-pi-zero/scripts/compile-on-zero.sh (on Pi 5 faster)"
fi

systemctl restart mmdvmhost
sleep 2
systemctl is-active mmdvmhost
journalctl -u mmdvmhost -n 8 --no-pager | grep -iE 'nextion|display|transparent|error' || true
echo ""
echo "Nextion enabled. Flash display first — see nextion/EDITOR-STEPS.txt"