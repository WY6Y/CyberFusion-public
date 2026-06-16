#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Phase 6: enable systemd units ==="
sudo cp "$ROOT/systemd/mmdvmhost.service" /etc/systemd/system/
sudo cp "$ROOT/systemd/ysfgateway.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mmdvmhost ysfgateway cyberfusion-dashboard cyberfusion-wifi-fallback
echo "Phase 6 done."