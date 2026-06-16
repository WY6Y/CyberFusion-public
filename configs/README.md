# Config templates

Copy and edit these before deploying. **Do not commit real passwords to a public repo.**

## Hotspot (fallback AP)

Edit `hostapd.conf`:

```bash
wpa_passphrase=YOUR_HOTSPOT_PASSWORD
```

## Client WiFi (home / mobile)

```bash
cp wifi-client.nmconnection.example wifi-client.nmconnection
# edit SSID and psk= lines — wifi-client.nmconnection is gitignored in the private backup workflow
```

Or use the dashboard / `wy6y-wifi-fallback add-network SSID PASSWORD priority`.

## Radio

Edit `mmdvmhost.ini` and `ysfgateway.ini`:

- `Callsign=` your callsign
- `RXFrequency` / `TXFrequency` your simplex or repeater pair
- `Latitude` / `Longitude` / `Location` as you prefer

Defaults use **WY6Y** and **438.800 MHz** as an example simplex setup.