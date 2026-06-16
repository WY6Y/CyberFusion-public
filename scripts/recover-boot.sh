#!/bin/bash
# Run ON THE PI ZERO when you regain access (SSH, AP mode, or keyboard).
# Fixes common post-reboot issues: WiFi stuck in AP, services crash-looping.
set -euo pipefail

echo "=== CyberFusion recovery ==="

# 1. Try to restore normal WiFi client (gets Tailscale back)
if command -v cyberfusion-wifi-fallback >/dev/null; then
  echo "Forcing WiFi client mode..."
  sudo cyberfusion-wifi-fallback force-client || true
  sleep 5
fi

# 2. Ensure UART enabled (for MMDVM board)
if grep -q '^enable_uart=0' /boot/firmware/config.txt 2>/dev/null; then
  sudo sed -i 's/^enable_uart=0/enable_uart=1/' /boot/firmware/config.txt
fi
grep -q '^enable_uart=1' /boot/firmware/config.txt 2>/dev/null || echo 'enable_uart=1' | sudo tee -a /boot/firmware/config.txt >/dev/null

# 3. Serial permissions for dialout
if [[ ! -f /etc/udev/rules.d/99-mmdvm-serial.rules ]]; then
  echo 'SUBSYSTEM=="tty", KERNEL=="ttyAMA0|ttyS0", GROUP="dialout", MODE="0660"' | \
    sudo tee /etc/udev/rules.d/99-mmdvm-serial.rules >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger
fi

# 4. Restart stack in order
sudo systemctl restart mosquitto
sleep 2
sudo systemctl restart mmdvmhost
sleep 4
sudo systemctl restart ysfgateway
sleep 2
sudo systemctl restart cyberfusion-dashboard
sudo systemctl restart tailscaled 2>/dev/null || true

echo ""
echo "Status:"
systemctl is-active mosquitto mmdvmhost ysfgateway cyberfusion-dashboard tailscaled 2>/dev/null || true
echo ""
echo "IPs:"
hostname -I
tailscale ip -4 2>/dev/null || echo "(tailscale not up yet — wait 30s)"
echo ""
echo "Dashboard: http://$(hostname -I | awk '{print $1}')/"
echo "If only AP: connect phone to CyberFusion-Hotspot → http://192.168.50.1/"