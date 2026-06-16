#!/bin/bash
# Push a WiFi client profile to the CyberFusion Pi Zero (retries until reachable).
# Set WIFI_SSID, WIFI_PSK, and PI_HOSTS before running.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIFI_SSID="${WIFI_SSID:?Set WIFI_SSID}"
WIFI_PSK="${WIFI_PSK:?Set WIFI_PSK}"
PI_HOSTS="${PI_HOSTS:-pi-zero.local}"
PI_USER="${PI_USER:-pi}"
PI_KEY="${PI_KEY:-$HOME/.ssh/id_ed25519}"
SSH_OPTS=(-i "$PI_KEY" -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)
INTERVAL="${INTERVAL:-20}"
MAX_TRIES="${MAX_TRIES:-0}"
KEYFILE="${KEYFILE:-$ROOT/configs/wifi-client.nmconnection}"

log() { echo "[$(date +%H:%M:%S)] $*"; }

reachable_host() {
  for h in $PI_HOSTS; do
    if ssh "${SSH_OPTS[@]}" "${PI_USER}@${h}" "echo ok" >/dev/null 2>&1; then
      echo "$h"
      return 0
    fi
  done
  return 1
}

apply_once() {
  local host
  host="$(reachable_host)" || return 1
  local PI="${PI_USER}@${host}"
  log "Connected via $host"

  scp "${SSH_OPTS[@]}" "$ROOT/scripts/wifi-fallback-light.sh" "$PI:/tmp/wy6y-wifi-fallback" || return 1
  [[ -f "$KEYFILE" ]] && scp "${SSH_OPTS[@]}" "$KEYFILE" "$PI:/tmp/wifi-client.nmconnection" || true

  ssh "${SSH_OPTS[@]}" "$PI" bash -s <<REMOTE
set -euo pipefail
IFACE=wlan0
WIFI_SSID='$WIFI_SSID'
WIFI_PSK='$WIFI_PSK'

install_script() {
  if sudo -n cp /tmp/wy6y-wifi-fallback /usr/local/bin/wy6y-wifi-fallback 2>/dev/null; then
    sudo -n chmod +x /usr/local/bin/wy6y-wifi-fallback
    return 0
  fi
  cp /tmp/wy6y-wifi-fallback /usr/local/bin/wy6y-wifi-fallback 2>/dev/null && chmod +x /usr/local/bin/wy6y-wifi-fallback
}

add_via_fallback() {
  sudo -n /usr/local/bin/wy6y-wifi-fallback add-network "\$WIFI_SSID" "\$WIFI_PSK" 100
}

nmcli_add() {
  local runner=("\$@")
  if "\${runner[@]}" -t -f NAME connection show 2>/dev/null | grep -Fxq "\$WIFI_SSID"; then
    "\${runner[@]}" connection modify "\$WIFI_SSID" \
      wifi.ssid "\$WIFI_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "\$WIFI_PSK" \
      connection.autoconnect yes connection.autoconnect-priority 100
  else
    "\${runner[@]}" connection add type wifi con-name "\$WIFI_SSID" ifname "\$IFACE" ssid "\$WIFI_SSID" \
      wifi-sec.key-mgmt wpa-psk wifi-sec.psk "\$WIFI_PSK" \
      connection.autoconnect yes connection.autoconnect-priority 100 ipv4.method auto ipv6.method auto
  fi
}

add_via_nmcli() { nmcli_add sudo -n nmcli; }
add_via_nmcli_user() { nmcli_add nmcli; }

add_via_keyfile() {
  [[ -f /tmp/wifi-client.nmconnection ]] || return 1
  sudo -n mkdir -p /etc/NetworkManager/system-connections
  sudo -n cp /tmp/wifi-client.nmconnection "/etc/NetworkManager/system-connections/\${WIFI_SSID}.nmconnection"
  sudo -n chmod 600 "/etc/NetworkManager/system-connections/\${WIFI_SSID}.nmconnection"
  sudo -n nmcli connection reload
}

install_script || true

if sudo -n cp /tmp/wy6y-wifi-fallback /usr/local/bin/wy6y-wifi-fallback 2>/dev/null; then
  sudo -n chmod +x /usr/local/bin/wy6y-wifi-fallback
fi

if add_via_fallback 2>/dev/null; then
  echo "OK: wy6y-wifi-fallback add-network"
elif add_via_nmcli 2>/dev/null; then
  echo "OK: sudo nmcli add"
elif add_via_nmcli_user 2>/dev/null; then
  echo "OK: user nmcli add"
elif add_via_keyfile 2>/dev/null; then
  echo "OK: keyfile import"
else
  echo "FAIL: run on the Pi:"
  echo "  sudo wy6y-wifi-fallback add-network \$WIFI_SSID <password> 100"
  exit 2
fi

nmcli -t -f NAME,AUTOCONNECT,connection.autoconnect-priority connection show | head -20
REMOTE
}

tries=0
while true; do
  tries=$((tries + 1))
  log "Attempt $tries → $PI_HOSTS"
  if apply_once; then
    log "WiFi profile saved on CyberFusion Pi"
    exit 0
  fi
  rc=$?
  if [[ "$MAX_TRIES" -gt 0 && "$tries" -ge "$MAX_TRIES" ]]; then
    log "Giving up after $tries tries (exit $rc)"
    exit "$rc"
  fi
  log "Pi not ready (exit $rc); retry in ${INTERVAL}s"
  sleep "$INTERVAL"
done