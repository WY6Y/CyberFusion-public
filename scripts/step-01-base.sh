#!/bin/bash
# Example tiny step script — copy to Pi Zero and run as: bash step-01-base.sh
set -euo pipefail
echo "=== Step: Base updates + hostname (light) ==="
sudo apt update
sudo hostnamectl set-hostname cyberfusion-hotspot || true
echo "127.0.1.1 cyberfusion-hotspot" | sudo tee -a /etc/hosts >/dev/null || true
echo "Done. Now run the serial step."
