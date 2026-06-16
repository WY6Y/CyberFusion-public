# CyberFusion — Pi Zero YSF Hotspot

Lightweight **YSF-only** MMDVM hotspot for **Raspberry Pi Zero 2 W** and **AURSINC MMDVM v1.5.2** (UART hat).

Fork-friendly: edit callsign, frequency, WiFi, and dashboard labels before deploy.

## Features

- YSFGateway + local YSF Parrot echo test
- Web dashboard (Python stdlib only)
- WiFi client + fallback AP (`CyberFusion-Hotspot` by default)
- MQTT status, reflector linking, optional Nextion HMI assets
- `fix-modem.sh` for Pi Zero UART / serial console issues

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

## License note

MMDVMHost and YSFClients sources are GPL (G4KLX). This repo bundles configs and deployment glue around those projects.