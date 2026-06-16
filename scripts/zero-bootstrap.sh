#!/bin/bash
# Run this ON THE PI ZERO — fetches package from Pi 5 build host over Tailscale.
# No scp/SSH from Pi 5 needed. Edit PI5_IP if your build host IP changes.
set -euo pipefail

PI5_IP="${PI5_IP:-100.106.79.105}"
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