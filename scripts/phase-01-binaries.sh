#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Phase 1: binaries + logs + group ==="
sudo mkdir -p /var/log/mmdvm /var/log/ysfgateway /usr/local/bin /usr/local/etc
sudo groupadd -f mmdvm
sudo usermod -aG mmdvm,dialout "$USER" || true
[[ -x "$ROOT/binaries/MMDVMHost" ]] && sudo cp "$ROOT/binaries/MMDVMHost" /usr/local/bin/
[[ -x "$ROOT/binaries/YSFGateway" ]] && sudo cp "$ROOT/binaries/YSFGateway" /usr/local/bin/
sudo chmod +x /usr/local/bin/MMDVMHost /usr/local/bin/YSFGateway
ls -la /usr/local/bin/MMDVMHost /usr/local/bin/YSFGateway
echo "Phase 1 done."