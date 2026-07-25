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

When it comes up, open **`http://<pi-zero-ip>:5000`** on your LAN. That is the
whole install — no VPN, no reverse proxy, no certificates. See below if you want
more than that.

## Access & networking — pick a tier

**You do not need Tailscale, Caddy, or HTTPS to run this hotspot.** The project is
built in tiers; stop at whichever one you need.

### Tier 1 — LAN only (default, no extra dependencies)

Browse to `http://<pi-zero-ip>:5000` from any device on the same network.
Everything that controls the radio works here: reflector linking, room search,
quick buttons, live traffic, and WiFi management.

Nothing else to install. If this is all you want, you are done.

### Tier 2 — Remote access from outside your LAN

Put the Pi on any overlay network / VPN and reach the same port 5000. Any of
these work; the dashboard neither knows nor cares which:

- **Tailscale** — what this repo's helper scripts happen to use
- **WireGuard**, **ZeroTier**, **Nebula**, or an existing VPN
- Your own reverse proxy on a host you already expose

The scripts call `tailscale` in a few places purely to *print* a convenient URL,
and every one of those calls falls back cleanly when Tailscale is absent
(`tailscale ip -4 2>/dev/null || hostname -I`). `ysf-status` simply reports an
empty `tailscale_ip`, and the dashboard leaves that field blank.

Do **not** port-forward this to the public internet — there is no login. See
[Security notes](#security-notes).

### Tier 3 — PWA install and phone-GPS APRS (needs HTTPS)

Only two features require HTTPS, because browsers only grant them to a
[secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts):

| Feature | Works on plain HTTP? |
|---------|----------------------|
| Reflector linking, room search, traffic, WiFi | **Yes** |
| "Add to Home Screen" / installable PWA | No — needs HTTPS |
| APRS tab phone GPS (Geolocation API) | No — needs HTTPS |

The certificate has to be one the *phone* already trusts, so a bare
self-signed cert is not enough on its own. Three practical routes:

| Route | Effort | Notes |
|-------|--------|-------|
| **Tailscale cert** | Easiest | `scripts/setup-https-pwa.sh`; cert is publicly trusted, no CA to install |
| **Caddy internal CA** | Medium | `caddy/Caddyfile`; you must install Caddy's root CA on each device |
| **Let's Encrypt (DNS-01)** | Most setup | Needs a real domain + DNS API credentials; works without exposing port 80 |

The UI degrades honestly: over plain HTTP it hides the install prompt and tells
you what to open instead, rather than failing silently.

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

The dashboard listens on **port 5000** on the Pi Zero and is reachable there
directly (tier 1). Optionally, a reverse proxy on another always-on host can map
a friendly hostname to `<pi-zero>:5000` — `caddy/Caddyfile` has a worked example
with Tailscale-cert, internal-CA, and Let's Encrypt variants.

**Dashboard app lives on the Pi Zero at:** `/opt/cyberfusion-dashboard/`

| File | Purpose |
|------|---------|
| `cyberfusion-dash.py` | Python stdlib HTTP server (ThreadingTCPServer) |
| `static/index.html` | Dashboard UI |
| `static/manifest.json` | PWA manifest (`start_url: "/"`, `scope: "/"`) |
| `static/sw.js` | Service worker (served at `/sw.js`) |
| `static/icons/` | PNG icons — 192px + 512px (cyberpunk radio tower, neon cyan/magenta) |

### PWA install (tier 3 — optional)

Skip this entirely if you are happy browsing to `http://<pi-zero-ip>:5000`.

**Prerequisite:** HTTPS, with a certificate the device already trusts.

- **Tailscale cert** (`scripts/setup-https-pwa.sh`) — publicly trusted, nothing
  to install on the phone.
- **Caddy internal CA** — install Caddy's root CA on the device first (served at
  `/caddy-ca.crt` by any site Caddy serves), then enable it under Settings →
  General → About → Certificate Trust Settings (iOS).
- **Let's Encrypt** — if you already have a domain, a DNS-01 cert works without
  exposing anything publicly.

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

**Link targets are names, not YSF numbers.** `ysf-link` writes `Startup=` in
`/etc/ysfgateway`, and YSFGateway resolves that with `findByName()` only — a bare
`32453` never resolves. The name it matches is the one it composes itself in
`YSFReflectors.cpp`: `"<country>-<name>"`, or `"XX-<name>"` when the host entry
sets `use_xx_prefix`. So reflector `KCWide` (designator 32453, country US) is
linked as **`US-KCWide`**. Matching is case-insensitive and compares only the
first 16 characters.

You can still *search* by number in the dashboard — type `32453` or `YSF32453`
and it will find the room and fill in the correct target for you.

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
