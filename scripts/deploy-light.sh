#!/bin/bash
# CyberFusion — light phased deploy for Pi Zero (or test host)
# Run: bash ~/cyberfusion-pi-zero/scripts/deploy-light.sh
# Each phase pauses briefly and prints status. Stop on first error.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pause() { echo "--- pause 2s ---"; sleep 2; }

need_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo "sudo password required — you may be prompted once."
    sudo true
  fi
}

echo "=== Phase 1: logs, group, binaries ==="
need_sudo
sudo mkdir -p /var/log/mmdvm /var/log/ysfgateway /usr/local/bin /usr/local/etc
sudo groupadd -f mmdvm
sudo usermod -aG mmdvm,dialout "$USER" || true
if [[ -x "$ROOT/binaries/MMDVMHost" ]]; then
  sudo cp "$ROOT/binaries/MMDVMHost" /usr/local/bin/MMDVMHost
fi
if [[ -x "$ROOT/binaries/YSFGateway" ]]; then
  sudo cp "$ROOT/binaries/YSFGateway" /usr/local/bin/YSFGateway
fi
sudo chmod +x /usr/local/bin/MMDVMHost /usr/local/bin/YSFGateway 2>/dev/null || true
ls -la /usr/local/bin/MMDVMHost /usr/local/bin/YSFGateway
pause

echo "=== Phase 2: configs + control scripts ==="
sudo cp "$ROOT/configs/mmdvmhost.ini" /etc/mmdvmhost
sudo cp "$ROOT/configs/ysfgateway.ini" /etc/ysfgateway
sudo cp "$ROOT/scripts/ysf-link" /usr/local/bin/
sudo cp "$ROOT/scripts/ysf-unlink" /usr/local/bin/
sudo cp "$ROOT/scripts/ysf-status" /usr/local/bin/
sudo chmod +x /usr/local/bin/ysf-link /usr/local/bin/ysf-unlink /usr/local/bin/ysf-status
echo "$USER ALL=(ALL) NOPASSWD: /usr/local/bin/ysf-link, /usr/local/bin/ysf-unlink, /usr/local/bin/ysf-status, /usr/local/bin/cyberfusion-wifi-fallback, /usr/bin/nmcli, /bin/systemctl restart mmdvmhost, /bin/systemctl restart ysfgateway, /bin/systemctl stop ysfgateway, /bin/systemctl start ysfgateway" | sudo tee /etc/sudoers.d/cyberfusion >/dev/null
sudo chmod 440 /etc/sudoers.d/cyberfusion
pause

echo "=== Phase 3: YSFHosts reflector list (JSON) ==="
if [[ -s "$ROOT/configs/YSFHosts-min.json" ]]; then
  sudo cp "$ROOT/configs/YSFHosts-min.json" /usr/local/etc/YSFHosts-min.json
else
  sudo curl -fsSL -A "YSFGateway - G4KLX" -o /usr/local/etc/YSFHosts-min.json \
    https://hostfiles.refcheck.radio/YSFHosts.json || \
    echo "WARN: could not fetch YSFHosts"
fi
sudo chown pi:mmdvm /usr/local/etc/YSFHosts-min.json 2>/dev/null || true
wc -c /usr/local/etc/YSFHosts-min.json 2>/dev/null || true
pause

echo "=== Phase 4: WiFi fallback ==="
sudo cp "$ROOT/scripts/wifi-fallback-light.sh" /usr/local/bin/cyberfusion-wifi-fallback
sudo chmod +x /usr/local/bin/cyberfusion-wifi-fallback
sudo cp "$ROOT/configs/hostapd.conf" /etc/hostapd/hostapd.conf
sudo mkdir -p /etc/dnsmasq.d
sudo cp "$ROOT/configs/dnsmasq.conf" /etc/dnsmasq.d/cyberfusion.conf
sudo cp "$ROOT/systemd/cyberfusion-wifi-fallback.service" /etc/systemd/system/
pause

echo "=== Phase 5: dashboard ==="
sudo mkdir -p /opt/cyberfusion-dashboard/static
sudo cp "$ROOT/dashboard/cyberfusion-dash.py" /opt/cyberfusion-dashboard/
sudo cp -r "$ROOT/dashboard/static/"* /opt/cyberfusion-dashboard/static/
sudo chown -R "$USER:$USER" /opt/cyberfusion-dashboard
python3 -m py_compile /opt/cyberfusion-dashboard/cyberfusion-dash.py
sudo cp "$ROOT/systemd/cyberfusion-dashboard.service" /etc/systemd/system/
pause

echo "=== Phase 6: MMDVM + YSF systemd ==="
sudo cp "$ROOT/systemd/mmdvmhost.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/ysfgateway.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mmdvmhost ysfgateway cyberfusion-dashboard cyberfusion-wifi-fallback
pause

echo "=== Phase 7: start services (one at a time) ==="
sudo systemctl start mmdvmhost
sleep 3
sudo systemctl start ysfgateway
sleep 2
sudo systemctl start cyberfusion-dashboard
sleep 1
sudo systemctl is-active mmdvmhost ysfgateway cyberfusion-dashboard || true
pause

echo "=== Deploy complete ==="
echo "Dashboard: http://$(hostname -I | awk '{print $1}')/"
echo "Tailscale:  http://$(tailscale ip -4 2>/dev/null || echo 'n/a')/"
echo "AP mode:    http://192.168.50.1/  (SSID CyberFusion-Hotspot)"
echo "Test room:  sudo ysf-link YSF23453"