#!/bin/bash
# Run this on the TARGET Pi Zero ONLY, after a small "build deps" apt step.
# It is intentionally single-job and can be run in tmux.
set -euo pipefail
echo "=== Compile MMDVMHost + YSFGateway on Pi Zero (light) ==="
echo "This can take 20-50 minutes. Use tmux and nice if wanted."
sleep 3

mkdir -p ~/build-hotspot
cd ~/build-hotspot

if [[ ! -d MMDVMHost ]]; then
  git clone --depth 1 https://github.com/g4klx/MMDVMHost.git
fi
if [[ ! -d YSFClients ]]; then
  git clone --depth 1 https://github.com/g4klx/YSFClients.git
fi

cd MMDVMHost
make clean || true
# For minimal, you may need libmosquitto-dev already installed in a prior step
make -j1 || { echo "Build had issues (missing headers?). Install libmosquitto-dev and retry."; exit 1; }
sudo cp MMDVM-Host /usr/local/bin/MMDVMHost
sudo chmod +x /usr/local/bin/MMDVMHost
echo "MMDVMHost installed"

cd ../YSFClients/YSFGateway
make clean || true
make -j1 || true
sudo cp YSFGateway /usr/local/bin/YSFGateway
sudo chmod +x /usr/local/bin/YSFGateway
echo "YSFGateway installed"

echo "Done. Binaries in /usr/local/bin"
ls -l /usr/local/bin/MMDVMHost /usr/local/bin/YSFGateway
