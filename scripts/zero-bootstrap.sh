#!/bin/bash
# Run this ON THE PI ZERO — fetches package from Pi 5 build host over Tailscale.
# No scp/SSH from Pi 5 needed. Set PI5_IP to your build host (e.g. its
# Tailscale IP or LAN address) before running.
set -euo pipefail

PI5_IP="${PI5_IP:-}"
if [[ -z "$PI5_IP" ]]; then
  echo "Set PI5_IP to the build host serving the package, e.g.:" >&2
  echo "  PI5_IP=192.0.2.10 bash $0" >&2
  exit 1
fi
PI5_PORT="${PI5_PORT:-8765}"
PKG="cyberfusion-pi-zero-pkg.tar.gz"
URL="http://${PI5_IP}:${PI5_PORT}/${PKG}"

echo "Fetching $URL ..."
curl -fSL -o ~/"$PKG" "$URL" || wget -qO ~/"$PKG" "$URL"
cd ~
tar xzf "$PKG"
echo "Extracted. Starting phased deploy..."
sleep 2
bash ~/cyberfusion-pi-zero/scripts/deploy-light.sh