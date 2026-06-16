#!/bin/bash
set -euo pipefail
echo "=== Phase 7: start services (slow) ==="
sudo systemctl start mmdvmhost
sleep 3
sudo systemctl start ysfgateway
sleep 2
sudo systemctl start cyberfusion-dashboard
sleep 1
systemctl is-active mmdvmhost ysfgateway cyberfusion-dashboard || true
echo ""
echo "Dashboard: http://$(hostname -I | awk '{print $1}')/"
echo "Tailscale: http://$(tailscale ip -4 2>/dev/null || echo n/a)/"
echo "Phase 7 done."