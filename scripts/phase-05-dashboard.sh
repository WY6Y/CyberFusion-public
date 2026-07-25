#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Phase 5: dashboard ==="
sudo mkdir -p /opt/cyberfusion-dashboard/static
sudo cp "$ROOT/dashboard/cyberfusion-dash.py" /opt/cyberfusion-dashboard/
# APRS-IS mobile tab (stdlib) — independent of CyberAPRS
if [[ -f "$ROOT/dashboard/aprs_is.py" ]]; then
  sudo cp "$ROOT/dashboard/aprs_is.py" /opt/cyberfusion-dashboard/
fi
sudo cp -r "$ROOT/dashboard/static/"* /opt/cyberfusion-dashboard/static/
sudo chown -R "$USER:$USER" /opt/cyberfusion-dashboard
python3 -m py_compile /opt/cyberfusion-dashboard/cyberfusion-dash.py
python3 -m py_compile /opt/cyberfusion-dashboard/aprs_is.py 2>/dev/null || true
sudo cp "$ROOT/systemd/cyberfusion-dashboard.service" /etc/systemd/system/
echo "Phase 5 done."