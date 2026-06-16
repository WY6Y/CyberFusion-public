#!/bin/bash
# Run this on the Pi 5 (build host) only.
# It attempts to produce ready binaries/ using local extraction.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
echo "=== Prepare binaries on Pi 5 (isolated) ==="
mkdir -p binaries

# If you have already built in build/, copy them
if [[ -x build/MMDVMHost/MMDVM-Host ]]; then
  cp build/MMDVMHost/MMDVM-Host binaries/MMDVMHost
  echo "Copied MMDVMHost"
fi
if [[ -x build/YSFClients/YSFGateway/YSFGateway ]]; then
  cp build/YSFClients/YSFGateway/YSFGateway binaries/YSFGateway
  echo "Copied YSFGateway"
fi

ls -l binaries/ || echo "Binaries dir ready for manual copy after successful build on target or here."

echo "On the Pi Zero you can also run: bash scripts/compile-on-zero.sh (after installing build deps in small steps)"
