#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PSK="${WIFI_PSK:-}"

echo "=== Phase 4: WiFi fallback ==="
sudo cp "$ROOT/scripts/wifi-fallback-light.sh" /usr/local/bin/wy6y-wifi-fallback
sudo chmod +x /usr/local/bin/wy6y-wifi-fallback
sudo cp "$ROOT/configs/hostapd.conf" /etc/hostapd/hostapd.conf
sudo mkdir -p /etc/dnsmasq.d
sudo cp "$ROOT/configs/dnsmasq.conf" /etc/dnsmasq.d/cyberfusion.conf
sudo cp "$ROOT/systemd/cyberfusion-wifi-fallback.service" /etc/systemd/system/
if [[ -f "$ROOT/configs/wifi-client.nmconnection" ]]; then
  sudo mkdir -p /etc/NetworkManager/system-connections
  sudo cp "$ROOT/configs/wifi-client.nmconnection" /etc/NetworkManager/system-connections/wifi-client.nmconnection
  sudo chmod 600 /etc/NetworkManager/system-connections/wifi-client.nmconnection
  sudo nmcli connection reload 2>/dev/null || true
fi
if [[ -n "$WIFI_SSID" && -n "$WIFI_PSK" ]]; then
  /usr/local/bin/wy6y-wifi-fallback add-network "$WIFI_SSID" "$WIFI_PSK" 100 2>/dev/null || true
else
  echo "Tip: copy configs/wifi-client.nmconnection.example → configs/wifi-client.nmconnection"
  echo "     or run: WIFI_SSID=... WIFI_PSK=... bash scripts/phase-04-wifi.sh"
fi
echo "Phase 4 done."