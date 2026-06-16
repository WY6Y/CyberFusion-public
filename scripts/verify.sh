#!/bin/bash
# Quick health check after deploy. No sudo needed for most checks.
set -uo pipefail

ok=0; warn=0; fail=0
pass() { echo "  OK   $1"; ok=$((ok+1)); }
warn() { echo "  WARN $1"; warn=$((warn+1)); }
fail() { echo "  FAIL $1"; fail=$((fail+1)); }

echo "=== CyberFusion verify ==="

[[ -x /usr/local/bin/MMDVMHost ]] && pass "MMDVMHost binary" || fail "MMDVMHost binary"
[[ -x /usr/local/bin/YSFGateway ]] && pass "YSFGateway binary" || fail "YSFGateway binary"
[[ -f /etc/mmdvmhost ]] && pass "/etc/mmdvmhost" || fail "/etc/mmdvmhost"
[[ -f /etc/ysfgateway ]] && pass "/etc/ysfgateway" || fail "/etc/ysfgateway"
[[ -s /usr/local/etc/YSFHosts.json ]] && pass "YSFHosts.json" || fail "YSFHosts.json"
[[ -x /usr/local/bin/ysf-link ]] && pass "ysf-link script" || fail "ysf-link script"
[[ -f /opt/cyberfusion-dashboard/cyberfusion-dash.py ]] && pass "dashboard installed" || fail "dashboard installed"

python3 -m py_compile /opt/cyberfusion-dashboard/cyberfusion-dash.py 2>/dev/null \
  && pass "dashboard syntax" || fail "dashboard syntax"

for svc in mmdvmhost ysfgateway cyberfusion-dashboard; do
  st=$(systemctl is-active "$svc" 2>/dev/null || echo inactive)
  if [[ "$st" == "active" ]]; then pass "$svc service active"
  else warn "$svc service: $st"; fi
done

ip=$(hostname -I 2>/dev/null | awk '{print $1}')
ts=$(tailscale ip -4 2>/dev/null || true)
echo ""
echo "Dashboard URLs:"
[[ -n "$ip" ]] && echo "  http://$ip/"
[[ -n "$ts" ]] && echo "  http://$ts/"
echo "  http://192.168.50.1/  (AP mode)"
echo ""
echo "Summary: $ok passed, $warn warnings, $fail failed"
[[ $fail -eq 0 ]]