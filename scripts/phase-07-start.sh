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
# Dashboard port follows PORT= in the systemd unit (default 5000).
DASH_PORT="$(systemctl show cyberfusion-dashboard -p Environment 2>/dev/null | tr ' ' '\n' | sed -n 's/^PORT=//p' | head -1)"
DASH_PORT="${DASH_PORT:-5000}"
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):${DASH_PORT}/"
TS_IP="$(tailscale ip -4 2>/dev/null || true)"
if [ -n "$TS_IP" ]; then echo "Remote (Tailscale): http://${TS_IP}:${DASH_PORT}/"; fi
echo "Phase 7 done."