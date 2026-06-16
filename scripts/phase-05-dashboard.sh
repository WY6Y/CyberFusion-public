#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Phase 5: dashboard ==="
sudo mkdir -p /opt/cyberfusion-dashboard/static
sudo cp "$ROOT/dashboard/cyberfusion-dash.py" /opt/cyberfusion-dashboard/
sudo cp -r "$ROOT/dashboard/static/"* /opt/cyberfusion-dashboard/static/
sudo chown -R "$USER:$USER" /opt/cyberfusion-dashboard
python3 -m py_compile /opt/cyberfusion-dashboard/cyberfusion-dash.py
sudo cp "$ROOT/systemd/cyberfusion-dashboard.service" /etc/systemd/system/
echo "Phase 5 done."