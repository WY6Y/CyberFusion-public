#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Phase 2: configs + ysf scripts + sudoers ==="
sudo cp "$ROOT/configs/mmdvmhost.ini" /etc/mmdvmhost
sudo cp "$ROOT/configs/ysfgateway.ini" /etc/ysfgateway
sudo cp "$ROOT/scripts/ysf-link" /usr/local/bin/
sudo cp "$ROOT/scripts/ysf-unlink" /usr/local/bin/
sudo cp "$ROOT/scripts/ysf-status" /usr/local/bin/
sudo chmod +x /usr/local/bin/ysf-link /usr/local/bin/ysf-unlink /usr/local/bin/ysf-status
echo "$USER ALL=(ALL) NOPASSWD: /usr/local/bin/ysf-link, /usr/local/bin/ysf-unlink, /usr/local/bin/ysf-status, /usr/local/bin/cyberfusion-wifi-fallback, /usr/bin/nmcli, /bin/systemctl restart mmdvmhost, /bin/systemctl restart ysfgateway, /bin/systemctl stop ysfgateway, /bin/systemctl start ysfgateway" | sudo tee /etc/sudoers.d/cyberfusion >/dev/null
sudo chmod 440 /etc/sudoers.d/cyberfusion
echo "Phase 2 done. Edit /etc/mmdvmhost if needed (callsign, freq, port)."