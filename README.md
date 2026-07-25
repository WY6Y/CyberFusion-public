# CyberFusion — Pi Zero YSF Hotspot

Lightweight **YSF-only** MMDVM hotspot for **Raspberry Pi Zero 2 W** and **AURSINC MMDVM v1.5.2** (UART hat).

Fork-friendly: edit callsign, frequency, WiFi, and dashboard labels before deploy.

## Features

- YSFGateway + local YSF Parrot echo test
- Web dashboard (Python stdlib only) — installable as a PWA
- WiFi client + fallback AP (`CyberFusion-Hotspot` by default)
- MQTT status, reflector linking, optional Nextion HMI assets
- `fix-modem.sh` for Pi Zero UART / serial console issues
- **APRS mobile tab** (IS-only position beacon + nearby discovery) — phone GPS → Pi Zero → APRS-IS

### APRS tab — IS-only, not an RF digi

If you already run an RF digipeater/IGate, this is **completely separate** from it.

| | CyberFusion APRS tab | A typical RF digi/IGate |
|--|----------------------|-------------------------|
| Where | Pi Zero dashboard PWA | Separate host + Direwolf/TNC |
| Medium | **APRS-IS only** (`TCPIP*`) | RF digi + IGate |
| GPS | Phone browser geolocation | Fixed site / RF mobiles |
| Default SSID | `N0CALL-9` (mobile) | e.g. `-7` digi, `-13` WX |
| Code | `dashboard/aprs_is.py` (stdlib) | separate project |

Use an SSID here that you are not already using on RF. No shared process, no shared
MQTT topics required, and no RF TX from the hotspot. The phone must keep the PWA open
(HTTPS) while beaconing — the Pi has no GPS of its own.

## Quick start

1. Clone this repo.
2. **Customize** — see `configs/README.md` and `configs/customize.example.env`.
3. Follow `docs/STEP-BY-STEP-FROM-FRESH.md` phase by phase.
4. Pre-built ARM binaries are in `binaries/`; rebuild from `build/` if needed.

## Customize (minimum)

| Setting | File / env |
|---------|------------|
| Callsign | `configs/mmdvmhost.ini`, `configs/ysfgateway.ini` |
| Frequency | same + `HOTSPOT_FREQ_MHZ` for dashboard |
| Hotspot SSID/password | `configs/hostapd.conf` |
| Home WiFi | `configs/wifi-client.nmconnection.example` → copy & edit |
| Dashboard title | `SITE_TITLE`, `LOCAL_CALLSIGN` in `systemd/cyberfusion-dashboard.service` |
| Linux user | `User=pi` in `systemd/*.service` (change if not using `pi`) |

## Parrot test

```bash
sudo ysf-link "ZZ Parrot"
# PTT 3+ seconds on your frequency, wait ~3s for echo
```

## Hardware

- Raspberry Pi Zero 2 W
- MMDVM_HS_Hat v1.5.2 on `/dev/serial0`
- YSF-capable radio in DN mode
- Optional Nextion 2.4" (`nextion/`)

## Deployment layout

The dashboard listens on port 5000 on the Pi Zero. A common setup is to put a
reverse proxy (Caddy/nginx) on another always-on host and proxy a friendly
hostname to `<pi-zero>:5000` — see `caddy/Caddyfile` for a worked example.

**Dashboard app lives on the Pi Zero at:** `/opt/cyberfusion-dashboard/`

| File | Purpose |
|------|---------|
| `cyberfusion-dash.py` | Python stdlib HTTP server (ThreadingTCPServer) |
| `static/index.html` | Dashboard UI |
| `static/manifest.json` | PWA manifest (`start_url: "/"`, `scope: "/"`) |
| `static/sw.js` | Service worker (served at `/sw.js`) |
| `static/icons/` | PNG icons — 192px + 512px (cyberpunk radio tower, neon cyan/magenta) |

### PWA install

**Prerequisite:** the device must trust whatever CA issued the dashboard's cert.
With a Tailscale-issued cert (`tailscale cert`, see `scripts/setup-https-pwa.sh`)
that is already the case. If you front it with Caddy's *internal* CA instead,
install that CA on the device first — it is served at `/caddy-ca.crt` on any site
Caddy is serving — then enable it under Settings → General → About →
Certificate Trust Settings (iOS).

- **iOS Safari:** Share → Add to Home Screen
- **Android Chrome:** Install App banner or browser menu → Install app

If the home screen icon shows a white screen after install, delete it and re-add — the old PWA may have been cached with a stale service worker.

### Room linking

```bash
# On Pi Zero:
sudo ysf-link "US-Kansas-City"   # link to a room
sudo ysf-unlink                  # disconnect
cat /var/run/cyberfusion-last    # see currently linked room
```

The dashboard UI quick-buttons and room search call `/api/link` which runs `ysf-link` server-side.

### Service management (Pi Zero)

```bash
sudo systemctl restart cyberfusion-dashboard
sudo systemctl status cyberfusion-dashboard
sudo journalctl -u cyberfusion-dashboard -f
```

## Security notes

The dashboard is built for a **trusted LAN / VPN (Tailscale) network** and has
**no login**. Anyone who can reach port 5000 can link reflectors and manage WiFi
profiles. Do not port-forward it to the internet.

What the server does do:

- **Origin check on POST** — state-changing requests whose `Origin` disagrees with
  the `Host` they arrived on are rejected with 403, so a random web page you visit
  cannot silently relink your hotspot. Requests with no `Origin` (curl, scripts)
  are allowed, since anything able to send a raw request could reach the API
  anyway. Extra hostnames can be permitted with `ALLOWED_ORIGINS=a.example,b.example`.
- **Static paths are confined** to the dashboard's own directory.
- **Untrusted text is HTML-escaped** before display — reflector names, callsigns
  seen off the air, and nearby WiFi SSIDs are all attacker-influenced.

## License note

MMDVMHost and YSFClients sources are GPL (G4KLX). This repo bundles configs and deployment glue around those projects.
