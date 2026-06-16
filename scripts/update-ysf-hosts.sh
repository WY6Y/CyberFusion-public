#!/bin/bash
# Refresh YSF reflector list (JSON). Run weekly via cron or by hand.
set -euo pipefail
DEST="/usr/local/etc/YSFHosts.json"
TMP="$(mktemp)"
curl -fsSL -A "YSFGateway - G4KLX" -o "$TMP" https://hostfiles.refcheck.radio/YSFHosts.json
sudo install -m 644 "$TMP" "$DEST"
rm -f "$TMP"
echo "Updated $DEST ($(wc -c < "$DEST") bytes)"