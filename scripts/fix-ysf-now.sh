#!/bin/bash
# Fix YSFHosts parse failure on Pi Zero (full JSON too large for 512MB RAM).
# Run on the Pi Zero: bash fix-ysf-now.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$ROOT/configs/YSFHosts-min.json" ]] || ROOT="$HOME"

echo "Installing minimal YSFHosts (4 rooms)..."
sudo cp "$ROOT/configs/YSFHosts-min.json" /usr/local/etc/YSFHosts-min.json
sudo chown wy6y:mmdvm /usr/local/etc/YSFHosts-min.json
sudo cp "$ROOT/configs/ysfgateway.ini" /etc/ysfgateway
sudo systemctl restart ysfgateway
sleep 3
journalctl -u ysfgateway -n 8 --no-pager | grep -iE 'Loaded|startup|error|Unable' || true
echo "Done. Try linking: sudo ysf-link US-Kansas-City"