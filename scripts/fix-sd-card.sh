#!/bin/bash
# Run on Pi 5 / Grok build host with Pi Zero SD card root partition mounted.
# Usage: sudo bash fix-sd-card.sh /path/to/mounted/root
#
# Fixes: AP password, truck WiFi, SSH, wifi-fallback trap, wifi script, sudoers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${1:?Usage: sudo $0 /path/to/mounted/root}"

BOOT="${ROOT}/boot/firmware"
[[ -d "$BOOT" ]] || BOOT="${ROOT}/boot"

HOTSPOT_USER="${HOTSPOT_USER:-pi}"
AP_PASS="${AP_PASS:-CHANGE_ME_HOTSPOT_PASSWORD}"
AP_SSID="${AP_SSID:-CyberFusion-Hotspot}"
TRUCK_SSID="${TRUCK_SSID:-YOUR_WIFI_SSID}"
TRUCK_PSK="${TRUCK_PSK:-YOUR_WIFI_PASSWORD}"

echo "=== CyberFusion SD card fix ==="
echo "Root: $ROOT"
echo "Boot: $BOOT"
echo ""

# --- boot partition ---
if [[ -f "$BOOT/config.txt" ]]; then
  grep -v '^enable_uart=' "$BOOT/config.txt" > /tmp/config.txt.$$
  echo 'enable_uart=1' >> /tmp/config.txt.$$
  cp /tmp/config.txt.$$ "$BOOT/config.txt"
  rm /tmp/config.txt.$$
  echo "[ok] config.txt: enable_uart=1"
fi

if [[ -f "$BOOT/cmdline.txt" ]]; then
  sed -i 's/console=serial0,[0-9]* //g; s/console=ttyAMA0,[0-9]* //g; s/console=ttyS0,[0-9]* //g' "$BOOT/cmdline.txt"
  echo "[ok] cmdline.txt: serial console removed"
fi

# Prevent getty from holding ttyS0 (MMDVM hat needs this UART)
mkdir -p "$ROOT/etc/systemd/system"
ln -sf /dev/null "$ROOT/etc/systemd/system/serial-getty@ttyS0.service"
echo "[ok] serial-getty@ttyS0 disabled for MMDVM"

touch "$BOOT/ssh" 2>/dev/null || touch "$ROOT/boot/ssh" 2>/dev/null || true
echo "[ok] SSH enabled on boot partition"

# --- hostapd: known hotspot password ---
mkdir -p "$ROOT/etc/hostapd"
if [[ -f "$PKG/configs/hostapd.conf" ]]; then
  cp "$PKG/configs/hostapd.conf" "$ROOT/etc/hostapd/hostapd.conf"
else
  cat >"$ROOT/etc/hostapd/hostapd.conf" <<EOF
interface=wlan0
ssid=CyberFusion-Hotspot
hw_mode=g
channel=6
wpa=2
wpa_passphrase=${AP_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF
fi
# Force password in case file existed with wrong value
sed -i "s/^wpa_passphrase=.*/wpa_passphrase=${AP_PASS}/" "$ROOT/etc/hostapd/hostapd.conf"
sed -i "s/^ssid=.*/ssid=${AP_SSID}/" "$ROOT/etc/hostapd/hostapd.conf"
echo "[ok] hostapd: ${AP_SSID} password set"

# --- dnsmasq for AP mode ---
mkdir -p "$ROOT/etc/dnsmasq.d"
if [[ -f "$PKG/configs/dnsmasq.conf" ]]; then
  cp "$PKG/configs/dnsmasq.conf" "$ROOT/etc/dnsmasq.d/cyberfusion.conf"
  echo "[ok] dnsmasq AP config installed"
fi

# --- WiFi profiles (NetworkManager) ---
# NM ignores profiles unless root:root and mode 600 — this was likely the main bug.
NM_DIR="$ROOT/etc/NetworkManager/system-connections"
mkdir -p "$NM_DIR"

nm_fix_perms() {
  local f="$1"
  chmod 600 "$f"
  chown 0:0 "$f" 2>/dev/null || chown root:root "$f"
}

nm_set_key() {
  local file="$1" key="$2" val="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s/^${key}=.*/${key}=${val}/" "$file"
  else
    sed -i "/^\[connection\]/a ${key}=${val}" "$file"
  fi
}

if [[ -f "$PKG/configs/wifi-client.nmconnection" ]]; then
  cp "$PKG/configs/wifi-client.nmconnection" "$NM_DIR/wifi-client.nmconnection"
  nm_fix_perms "$NM_DIR/wifi-client.nmconnection"
  echo "[ok] client WiFi profile installed (root:root 600)"
fi

# Fix permissions on ALL connection files
for f in "$NM_DIR"/*; do
  [[ -f "$f" ]] && nm_fix_perms "$f"
done

# --- wifi-fallback script with add-network support ---
mkdir -p "$ROOT/usr/local/bin"
if [[ -f "$PKG/scripts/wifi-fallback-light.sh" ]]; then
  cp "$PKG/scripts/wifi-fallback-light.sh" "$ROOT/usr/local/bin/cyberfusion-wifi-fallback"
  chmod 755 "$ROOT/usr/local/bin/cyberfusion-wifi-fallback"
  echo "[ok] cyberfusion-wifi-fallback script updated"
fi

# --- wifi-fallback: keep as last-resort AP (75s after boot if no WiFi) ---
WANTS="$ROOT/etc/systemd/system/multi-user.target.wants"
mkdir -p "$WANTS"
if [[ -f "$ROOT/etc/systemd/system/cyberfusion-wifi-fallback.service" ]]; then
  ln -sf ../cyberfusion-wifi-fallback.service "$WANTS/cyberfusion-wifi-fallback.service"
  echo "[ok] wifi-fallback enabled (AP after 75s if no WiFi joins)"
else
  rm -f "$WANTS/cyberfusion-wifi-fallback.service" 2>/dev/null || true
  echo "[warn] cyberfusion-wifi-fallback.service missing — AP fallback not installed"
fi

# --- sudoers for dashboard + wifi tools ---
mkdir -p "$ROOT/etc/sudoers.d"
cat >"$ROOT/etc/sudoers.d/cyberfusion" <<SUDOERS
${HOTSPOT_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/ysf-link, /usr/local/bin/ysf-unlink, /usr/local/bin/ysf-status, /usr/local/bin/cyberfusion-wifi-fallback, /usr/bin/nmcli, /bin/systemctl restart mmdvmhost, /bin/systemctl restart ysfgateway, /bin/systemctl stop ysfgateway, /bin/systemctl start ysfgateway
SUDOERS
chmod 440 "$ROOT/etc/sudoers.d/cyberfusion"
echo "[ok] sudoers updated (passwordless wifi + ysf controls)"

# --- show what's on the card ---
echo ""
echo "=== WiFi profiles on card ==="
ls -la "$NM_DIR" 2>/dev/null || echo "(none)"
echo ""
echo "=== hostapd password line ==="
grep -E '^ssid=|^wpa_passphrase=' "$ROOT/etc/hostapd/hostapd.conf" 2>/dev/null || true
echo ""
echo "=== Done ==="
echo "1. Safely unmount SD card"
echo "2. Put it back in Pi Zero and power on"
echo "3. Wait 90s — joins ${TRUCK_SSID} or your saved home WiFi if in range"
echo "4. If no WiFi: hotspot CyberFusion-Hotspot / (password you set) → ssh pi@192.168.50.1"
echo "5. Once online: ssh pi@<pi-ip> or use Tailscale hostname"