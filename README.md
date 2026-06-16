# WY6Y CyberFusion — Pi Zero YSF Hotspot

Lightweight **YSF-only** MMDVM hotspot for **Raspberry Pi Zero 2 W** and **AURSINC MMDVM v1.5.2** (UART hat).

Built and staged on a Pi 5 build host; deployed to the Pi Zero with small phase scripts.

## Features

- YSFGateway + local YSF Parrot echo test
- Pi-Star-style web dashboard (Python stdlib only)
- WiFi client + **WY6Y-Hotspot** fallback AP
- MQTT status, reflector linking, Nextion HMI assets
- `fix-modem.sh` for Pi Zero UART / serial console issues

## Quick start

1. Clone this repo on your build machine or Pi Zero.
2. **Set your secrets** — see `configs/README.md` (hotspot password, WiFi client profile, callsign, frequency).
3. Follow `docs/STEP-BY-STEP-FROM-FRESH.md` phase by phase.
4. Pre-built ARM binaries are in `binaries/`; rebuild from `build/` if needed.

## Hardware

- Raspberry Pi Zero 2 W
- MMDVM_HS_Hat v1.5.2 on `/dev/serial0`
- YSF radio in DN mode (tested: Yaesu FT-70D @ 438.800 MHz)
- Optional Nextion display (`nextion/`)

## Parrot test

```bash
sudo /usr/local/bin/ysf-link "ZZ Parrot"
# PTT 3+ seconds on your frequency, wait ~3s for echo
```

## License note

MMDVMHost and YSFClients sources are GPL (G4KLX). This repo bundles configs and deployment glue around those projects.

73 — WY6Y