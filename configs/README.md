# Customize before deploy

Edit these templates for **your** callsign, frequency, location, and WiFi. Do not commit real passwords to a public fork.

## Quick checklist

1. Copy `customize.example.env` → `customize.env` (local only; gitignored).
2. Edit `mmdvmhost.ini` and `ysfgateway.ini` — `Callsign`, frequencies, lat/long, `Location`.
3. Edit `hostapd.conf` — `ssid` and `wpa_passphrase`.
4. Optional client WiFi: `cp wifi-client.nmconnection.example wifi-client.nmconnection` and edit SSID/psk.

## Files

| File | What to change |
|------|----------------|
| `mmdvmhost.ini` | Callsign, Id (DMR ID), RX/TX MHz, modem levels, UART port |
| `ysfgateway.ini` | Callsign, frequencies, `Startup` reflector (default `ZZ Parrot` for echo test) |
| `hostapd.conf` | AP SSID (`CyberFusion-Hotspot` or your name), hotspot password |
| `wifi-client.nmconnection.example` | Template for home/mobile WiFi |

## Dashboard / systemd

Set environment on the Pi (or in `systemd/cyberfusion-dashboard.service`):

```ini
Environment=LOCAL_CALLSIGN=YOURCALL
Environment=SITE_TITLE=YOUR HOTSPOT NAME
Environment=HOTSPOT_FREQ_MHZ=446.000
```

## Linux user

Default scripts assume user **`pi`**. If you use another account, set `HOTSPOT_USER` in `customize.env` and update `User=` in `systemd/*.service` before `phase-06-systemd.sh`.

## Parrot test

```bash
sudo ysf-link "ZZ Parrot"
# PTT 3+ seconds on your frequency, wait ~3s for echo
```