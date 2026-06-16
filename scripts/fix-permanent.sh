#!/bin/bash
# One-time permanent fix — run on Pi Zero: sudo bash fix-permanent.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
[[ $EUID -eq 0 ]] || { echo "Run with: sudo bash $0"; exit 1; }

echo "=== Permanent CyberFusion fix ==="

# Minimal YSF hosts (4 rooms — Pi Zero cannot parse 888KB file)
# YSFGateway opens Hosts with fstream (read+write); wy6y must own the file.
cp "$DIR/YSFHosts-min.json" /usr/local/etc/YSFHosts-min.json
chown wy6y:mmdvm /usr/local/etc/YSFHosts-min.json
chmod 644 /usr/local/etc/YSFHosts-min.json
cp "$DIR/ysfgateway.ini" /etc/ysfgateway
cp "$DIR/mmdvmhost.ini" /etc/mmdvmhost 2>/dev/null || true
sed -i 's|YSFHosts.json|YSFHosts-min.json|' /etc/ysfgateway
sed -i '/^\[FCS Network\]/,/^\[/ s/^Enable=1/Enable=0/' /etc/ysfgateway
sed -i '/^\[YSF Network\]/,/^\[/ s/^Port=4200$/Port=42000/' /etc/ysfgateway

# Control scripts + dashboard
cp "$DIR/ysf-status" /usr/local/bin/ysf-status
cp "$DIR/ysf-link" /usr/local/bin/ysf-link
chmod +x /usr/local/bin/ysf-{link,unlink,status}
cp "$DIR/cyberfusion-dash.py" /opt/cyberfusion-dashboard/
cp "$DIR/index.html" /opt/cyberfusion-dashboard/static/ 2>/dev/null || true
chown wy6y:wy6y /opt/cyberfusion-dashboard/cyberfusion-dash.py
cp "$DIR/cyberfusion-dashboard.service" /etc/systemd/system/ 2>/dev/null || true

# Stop manual YSF workaround, use systemd
pkill -x YSFGateway 2>/dev/null || true
crontab -u wy6y -l 2>/dev/null | grep -v ysfgateway-fixed | crontab -u wy6y - || true

[[ -x "$DIR/YSFParrot" ]] && cp "$DIR/YSFParrot" /usr/local/bin/YSFParrot && chmod +x /usr/local/bin/YSFParrot
[[ -f "$DIR/ysfparrot.service" ]] && cp "$DIR/ysfparrot.service" /etc/systemd/system/
[[ -f "$DIR/ysfgateway.service" ]] && cp "$DIR/ysfgateway.service" /etc/systemd/system/

systemctl daemon-reload
systemctl enable ysfparrot 2>/dev/null || true
systemctl restart mosquitto
sleep 2
systemctl restart ysfparrot
sleep 1
systemctl restart mmdvmhost
sleep 3
systemctl restart ysfgateway
sleep 2
systemctl restart cyberfusion-dashboard

echo ""
echo "Status:"
systemctl is-active mmdvmhost ysfgateway cyberfusion-dashboard tailscaled
journalctl -u ysfgateway -n 4 --no-pager | grep -iE 'Loaded|Linked|Unable' || true
echo ""
echo "Dashboard: http://$(tailscale ip -4 2>/dev/null || hostname -I | awk '{print $1}')/"