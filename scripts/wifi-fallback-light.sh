#!/bin/bash
# Ultra-light WiFi client with AP fallback for Pi Zero
# SSID: WY6Y-Hotspot   (edit /etc/hostapd/hostapd.conf for password)
set -euo pipefail

IFACE="wlan0"
AP_IP="192.168.50.1"
WAIT=75

log() { echo "[$(date +%H:%M:%S)] $*" | logger -t wifi-fb; echo "$*"; }

has_ip() { ip -4 addr show "$IFACE" 2>/dev/null | grep -q "inet "; }

is_up() { iw "$IFACE" link 2>/dev/null | grep -qi "connected" || nmcli -t -f GENERAL.STATE dev show "$IFACE" 2>/dev/null | grep -q "connected"; }

start_ap() {
  log "No client after ${WAIT}s — starting AP WY6Y-Hotspot"
  nmcli device set "$IFACE" managed no 2>/dev/null || true
  ip link set "$IFACE" down || true
  ip addr flush dev "$IFACE" || true
  ip link set "$IFACE" up
  ip addr add "${AP_IP}/24" dev "$IFACE" || true
  systemctl stop hostapd dnsmasq 2>/dev/null || true
  hostapd -B /etc/hostapd/hostapd.conf
  dnsmasq --conf-file=/etc/dnsmasq.d/cyberfusion.conf --pid-file=/run/dnsmasq-fb.pid
  log "AP running at $AP_IP"
}

stop_ap() {
  pkill -f "hostapd -B" 2>/dev/null || true
  pkill -f dnsmasq-fb 2>/dev/null || true
  ip addr flush dev "$IFACE" 2>/dev/null || true
  nmcli device set "$IFACE" managed yes 2>/dev/null || true
}

con_name_for() {
  local ssid="$1"
  local name="$ssid"
  name="${name// /_}"
  echo "$name"
}

find_connection() {
  local target="$1"
  if nmcli -t -f NAME connection show | grep -Fxq "$target"; then
    echo "$target"
    return 0
  fi
  nmcli -t -f NAME,802-11-wireless.ssid connection show | awk -F: -v ssid="$target" '
    $2 == ssid { print $1; exit }
  '
}

add_network() {
  local ssid="${1:-}" psk="${2:-}" prio="${3:-100}"
  [[ -z "$ssid" || -z "$psk" ]] && { log "Usage: add-network SSID PASSWORD [priority]"; exit 1; }
  local name
  name="$(con_name_for "$ssid")"
  local existing
  existing="$(find_connection "$ssid")"
  if [[ -n "$existing" ]]; then
    log "Updating existing profile: $existing"
    nmcli connection modify "$existing" \
      wifi.ssid "$ssid" \
      wifi-sec.key-mgmt wpa-psk \
      wifi-sec.psk "$psk" \
      connection.autoconnect yes \
      connection.autoconnect-priority "$prio"
  else
    log "Adding WiFi profile: $ssid"
    nmcli connection add type wifi con-name "$name" ifname "$IFACE" ssid "$ssid" \
      wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" \
      connection.autoconnect yes connection.autoconnect-priority "$prio" \
      ipv4.method auto ipv6.method auto
  fi
  log "Saved $ssid (priority $prio)"
}

is_ap() { pgrep -f "hostapd -B /etc/hostapd/hostapd.conf" >/dev/null 2>&1; }

wifi_status() {
  local mode="client" ssid="" ip="" active=""
  if is_ap; then
    mode="ap"
    ip="$AP_IP"
  else
    ssid="$(iwgetid -r "$IFACE" 2>/dev/null || true)"
    ip="$(ip -4 -o addr show "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
    active="$(nmcli -t -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true)"
  fi
  printf '{"mode":"%s","ssid":"%s","ip":"%s","active":"%s","ap_ssid":"WY6Y-Hotspot","ap_ip":"%s"}\n' \
    "$mode" "$ssid" "$ip" "$active" "$AP_IP"
}

list_networks() {
  nmcli -t -f NAME,TYPE,802-11-wireless.ssid,connection.autoconnect,connection.autoconnect-priority connection show \
    | awk -F: -v active="$(nmcli -t -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null || true)" '
      $2 == "802-11-wireless" && $1 != "" {
        ac = ($4 == "yes") ? "true" : "false"
        act = ($1 == active) ? "true" : "false"
        printf "%s|%s|%s|%s|%s\n", $1, $3, $5, ac, act
      }'
}

prepare_scan() {
  stop_ap
  nmcli device set "$IFACE" managed yes 2>/dev/null || true
  nmcli dev wifi rescan 2>/dev/null || true
  sleep 3
}

scan_networks() {
  prepare_scan
  nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE dev wifi list 2>/dev/null \
    | awk -F: '$1 != "" && $1 != "--" { print }' \
    | sort -t: -k2 -nr \
    | awk -F: '!seen[$1]++ { printf "%s|%s|%s|%s\n", $1, $2, $3, ($4=="*")?"true":"false" }'
}

connect_network() {
  local target="${1:-}"
  [[ -z "$target" ]] && { log "Usage: connect SSID-or-NAME"; exit 1; }
  local name
  name="$(find_connection "$target")"
  [[ -z "$name" ]] && { log "No saved profile for $target"; exit 1; }
  stop_ap
  nmcli device set "$IFACE" managed yes 2>/dev/null || true
  sleep 1
  log "Connecting to $name"
  nmcli connection up "$name"
}

delete_network() {
  local target="${1:-}"
  [[ -z "$target" ]] && { log "Usage: delete-network SSID-or-NAME"; exit 1; }
  local name
  name="$(find_connection "$target")"
  [[ -z "$name" ]] && { log "No profile for $target"; exit 1; }
  nmcli connection delete "$name"
  log "Deleted $name"
}

add_and_connect() {
  add_network "${1:-}" "${2:-}" "${3:-100}"
  sleep 1
  connect_network "${1:-}"
}

case "${1:-check}" in
  add-network) add_network "${2:-}" "${3:-}" "${4:-100}" ;;
  add-and-connect) add_and_connect "${2:-}" "${3:-}" "${4:-100}" ;;
  status) wifi_status ;;
  list-networks) list_networks ;;
  scan) scan_networks ;;
  connect) connect_network "${2:-}" ;;
  delete-network) delete_network "${2:-}" ;;
  force-ap) stop_ap; start_ap ;;
  force-client) stop_ap; nmcli device set "$IFACE" managed yes 2>/dev/null || true; nmcli dev connect "$IFACE" 2>/dev/null || nmcli device connect "$IFACE" 2>/dev/null || true ;;
  *)
    for i in $(seq 1 $WAIT); do
      if has_ip && is_up; then
        log "Client OK"; stop_ap; exit 0
      fi
      sleep 1
    done
    start_ap
    ;;
esac
