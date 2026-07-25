#!/bin/bash
set -euo pipefail
echo "Setting up Caddy for CyberFusion PWA on HTTPS (Tailscale)"
sudo apt update
sudo apt install -y caddy

sudo mkdir -p /etc/caddy/certs

echo "Obtain Tailscale cert (run on the target machine):"
echo "  sudo tailscale cert your-hotspot.your-tailnet.ts.net"
echo "Then copy the .crt and .key to /etc/caddy/certs/ on the machine."

sudo cp caddy/Caddyfile /etc/caddy/Caddyfile

echo "Make sure the dashboard is running on port 5000 (update service if needed)"
echo "Then: sudo systemctl reload caddy"
echo "Test: curl -I https://your-hotspot.your-tailnet.ts.net/"
