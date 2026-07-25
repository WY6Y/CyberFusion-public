#!/bin/bash
set -euo pipefail
echo "=== Setup HTTPS + PWA for CyberFusion on Tailscale domain ==="
echo "Run this on the CyberFusion machine (wy6y-cyberfusion-1)"

# 1. Deploy the dashboard if not done (assume source is there or use scp from dev)
# For now, assume /opt/cyberfusion-dashboard is set up and service running on 5000

sudo mkdir -p /etc/caddy/certs

# 2. Get Tailscale cert (must run on the cyberfusion node)
echo "Obtaining Tailscale cert..."
sudo tailscale cert your-hotspot.your-tailnet.ts.net || echo "Run manually if fails: sudo tailscale cert your-hotspot.your-tailnet.ts.net"

# Copy certs if generated in ~ or current dir
if [ -f your-hotspot.your-tailnet.ts.net.crt ]; then
  sudo cp your-hotspot.your-tailnet.ts.net.* /etc/caddy/certs/
fi

# 3. Install Caddy if needed
if ! command -v caddy >/dev/null; then
  echo "Installing Caddy..."
  sudo apt update
  sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
  sudo apt update
  sudo apt install -y caddy
fi

# 4. Install Caddyfile
sudo mkdir -p /etc/caddy
sudo cp caddy/Caddyfile /etc/caddy/Caddyfile || echo "Make sure caddy/Caddyfile is in current dir or copy manually"

# 5. Make sure dashboard runs on 5000
# Update service if needed
if [ -f /etc/systemd/system/cyberfusion-dashboard.service ]; then
  sudo sed -i 's|Environment=PORT=.*|Environment=PORT=5000|' /etc/systemd/system/cyberfusion-dashboard.service || true
  sudo systemctl daemon-reload
  sudo systemctl restart cyberfusion-dashboard.service
fi

# 6. Reload Caddy
sudo systemctl enable --now caddy
sudo caddy reload --config /etc/caddy/Caddyfile || sudo systemctl restart caddy

echo "Test with: curl -I https://your-hotspot.your-tailnet.ts.net/"
echo "For PWA: open the URL in Chrome, the install button should appear in the bar."
