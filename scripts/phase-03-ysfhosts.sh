#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Phase 3: YSFHosts.json ==="
if [[ -s "$ROOT/configs/YSFHosts-min.json" ]]; then
  sudo cp "$ROOT/configs/YSFHosts-min.json" /usr/local/etc/YSFHosts-min.json
else
  sudo curl -fsSL -A "YSFGateway - G4KLX" -o /usr/local/etc/YSFHosts-min.json \
    https://hostfiles.refcheck.radio/YSFHosts.json || true
fi
sudo chown wy6y:mmdvm /usr/local/etc/YSFHosts-min.json 2>/dev/null || true
wc -c /usr/local/etc/YSFHosts-min.json 2>/dev/null || true
echo "Phase 3 done."