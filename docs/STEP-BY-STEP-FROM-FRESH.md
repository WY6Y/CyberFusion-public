# CyberFusion — Pi Zero 2W YSF Hotspot (v1.5.2 board)
## Ultra Light, Step-by-Step Install from Fresh 64-bit Raspberry Pi OS Lite

**Goal**: Clean, stable system on **Pi Zero 2W** (or compatible 64-bit capable Zero) with MMDVM Hotspot Board v1.5.2.

**All heavy lifting prepared on your Pi 5**. You will only run small, fast commands on the target Pi Zero. No monolithic installer.

**Key points**:
- Every step is one small focused action (apt group of 3 packages, one config copy, one enable, etc.).
- Pre-built binaries will be provided (or build locally in one dedicated step).
- WiFi fallback is minimal.
- Dashboard is pure Python stdlib (no pip, no venv, no Flask).
- You copy files from Pi 5 → Pi Zero using `scp` (when both on same network) or by mounting the SD card on the Pi 5.

**Target hardware**:
- Raspberry Pi Zero 2 W (64-bit OS)
- MMDVM Hotspot Board v1.5.2 (stacks on GPIO, typically uses UART)
- Optional 2.4" Nextion (separate serial connection)

---

## Phase 0: Prepare on your Pi 5 (Build Host) — DO THIS FIRST

You are reading this on the Pi 5. Everything here stays in `~/CyberFusion-public/`. Nothing is installed or enabled on the Pi 5.

1. Make sure you have the latest files in this directory (the one containing `docs/`, `scripts/`, `configs/`, `binaries/` etc.).
2. (If not already) Pre-build or stage the two binaries (the project dir has a helper).

Run on Pi 5 (safe):

```bash
cd ~/CyberFusion-public
# The binaries/ folder should contain the final MMDVMHost and YSFGateway
# If empty, run the provided build helper (it only touches files inside this dir)
bash scripts/prepare-binaries.sh   # or follow the build notes below
ls -l binaries/
```

If `binaries/` has the two executables, great — you will copy them later.

---

## Phase 1: Fresh Image on Pi Zero

1. Download **Raspberry Pi OS Lite 64-bit** (Bookworm recommended) using Raspberry Pi Imager on any computer.
2. In Imager advanced options:
   - Set hostname: `cyberfusion-hotspot`
   - Enable SSH
   - Set username: `pi`, choose a good password
   - (Optional) Pre-configure your home WiFi SSID/password so first boot has network.
3. Write to SD card (at least 8 GB, preferably fast).
4. Insert into Pi Zero + MMDVM board + antenna.
5. Power on (use good 5V/2.5A+ supply — Pi Zero + board + Nextion needs it).
6. Find the IP (check your router or use `ping cyberfusion-hotspot.local` from another machine).
7. SSH in as `pi`.

On the Pi Zero console/SSH, run the steps below **one by one**. After each, read the output and confirm "OK" before the next.

---

## Phase 2: Base Identity & Serial (Tiny Steps)

**Step 2.1** — Confirm identity (already should be set by imager)

```bash
hostname
whoami
groups
```

**Step 2.2** — Update package lists only (very light)

```bash
sudo apt update
```

**Step 2.3** — Set/confirm hostname again if needed (fast)

```bash
sudo hostnamectl set-hostname cyberfusion-hotspot
echo "127.0.1.1 cyberfusion-hotspot" | sudo tee -a /etc/hosts
```

**Step 2.4** — Enable hardware UART, disable serial console (critical for MMDVM board)

Use raspi-config (non-interactive where possible):

```bash
sudo raspi-config nonint do_serial 0   # No login shell, yes hardware serial
```

Clean cmdline:

```bash
sudo sed -i 's/console=serial0,115200 //g; s/console=ttyAMA0,115200 //g' /boot/firmware/cmdline.txt 2>/dev/null || true
sudo sed -i 's/console=serial0,115200 //g; s/console=ttyAMA0,115200 //g' /boot/cmdline.txt 2>/dev/null || true
```

Add to config:

```bash
echo 'enable_uart=1' | sudo tee -a /boot/firmware/config.txt >/dev/null 2>&1 || \
echo 'enable_uart=1' | sudo tee -a /boot/config.txt >/dev/null 2>&1
```

Reboot now (small reboot):

```bash
sudo reboot
```

After reboot, SSH back in and verify:

```bash
ls -l /dev/serial0 /dev/ttyAMA0 2>/dev/null || true
groups $USER | grep -E 'dialout|mmdvm' || true
```

---

## Phase 3: Minimal Packages (Split into tiny groups — prevents freeze)

Do these **one group at a time**. Wait for each to finish and check disk/memory if worried.

**Step 3.1** Core essentials

```bash
sudo apt install -y git curl wget ca-certificates tmux htop vim
```

**Step 3.2** Build tools (only if you will compile on the Zero — skip if using pre-built binaries from Pi 5)

```bash
sudo apt install -y build-essential cmake make
```

**Step 3.3** Python (stdlib only — no pip)

```bash
sudo apt install -y python3
```

**Step 3.4** Network / WiFi / AP tools (light)

```bash
sudo apt install -y hostapd dnsmasq iw wpasupplicant network-manager avahi-daemon libnss-mdns
```

**Step 3.5** (Optional, only if building on Zero) Mosquitto dev for full compile (small)

```bash
sudo apt install -y libmosquitto-dev
```

After packages, clean a bit:

```bash
sudo apt clean
```

---

## Phase 4: Tailscale (Small & Independent)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=cyberfusion-hotspot --accept-routes
```

(If no internet yet, do this step later when you have WiFi or use phone tether.)

Enable the service:

```bash
sudo systemctl enable --now tailscaled
```

Test: `tailscale ip -4`

---

## Phase 5: Get the CyberFusion Files onto the Pi Zero

Two easy ways:

**A. scp from your Pi 5 (recommended while both on network)**

On your Pi 5:

```bash
cd ~/CyberFusion-public
scp -r configs scripts dashboard systemd docs pi@<pi-zero-ip>:~/
# Also the pre-built binaries if you have them
scp binaries/MMDVMHost binaries/YSFGateway pi@<pi-zero-ip>:~/binaries/ 2>/dev/null || echo "Will build on target or copy later"
```

**B. Mount SD card on Pi 5**

- Power off Pi Zero, remove SD.
- Insert SD into Pi 5 (use reader).
- Mount the root partition (usually `/dev/mmcblk0p2` or check `lsblk`).
- Copy the directories into the `/home/pi/` of the mounted rootfs (or your chosen username).
- Unmount, put SD back in Zero, boot.

---

## Phase 6: Install Pre-built Binaries (or Build if Needed)

**Preferred: Use pre-builts from Pi 5**

On Pi Zero:

```bash
sudo mkdir -p /usr/local/bin
sudo cp ~/binaries/MMDVMHost /usr/local/bin/MMDVMHost
sudo cp ~/binaries/YSFGateway /usr/local/bin/YSFGateway
sudo chmod +x /usr/local/bin/MMDVMHost /usr/local/bin/YSFGateway
ls -l /usr/local/bin/MMDVMHost /usr/local/bin/YSFGateway
```

**Alternative: Build on the Pi Zero (dedicated step, can take 20-40 min, run with nice)**

See `scripts/compile-on-zero.sh` (copy it over and run it after the build-deps step). It does shallow clone + make -j1.

---

## Phase 7: Place Configs, Logs, Control Scripts (Small)

```bash
# Create log dirs
sudo mkdir -p /var/log/mmdvm /var/log/ysfgateway
sudo groupadd -f mmdvm
sudo usermod -aG mmdvm,dialout pi

# Copy configs (edit callsign + frequencies + port first if needed)
sudo cp ~/configs/mmdvmhost.ini /etc/mmdvmhost
sudo cp ~/configs/ysfgateway.ini /etc/ysfgateway

# Control scripts (link/unlink/status)
sudo cp ~/scripts/ysf-link /usr/local/bin/
sudo cp ~/scripts/ysf-unlink /usr/local/bin/
sudo cp ~/scripts/ysf-status /usr/local/bin/
sudo chmod +x /usr/local/bin/ysf-*

# Sudoers for the dashboard user to call the controls without password
echo 'pi ALL=(ALL) NOPASSWD: /usr/local/bin/ysf-link, /usr/local/bin/ysf-unlink, /usr/local/bin/ysf-status, /bin/systemctl restart mmdvmhost, /bin/systemctl restart ysfgateway' | sudo tee /etc/sudoers.d/cyberfusion
sudo chmod 440 /etc/sudoers.d/cyberfusion
```

**Important edits** (use `sudo nano`):

- In `/etc/mmdvmhost`: Set your Callsign, RX/TX Frequency, and especially `[Modem] Port=` (usually `/dev/ttyAMA0` or `/dev/serial0` for these v1.5.2 GPIO boards).
- For Nextion (if using): Fill the `[Nextion]` section. Port may need to be a second serial (USB-TTL adapter recommended for Pi Zero).
- In `/etc/ysfgateway`: Set Callsign, initial `Startup=` (can be empty).

---

## Phase 8: YSFHosts (reflectors list)

```bash
sudo mkdir -p /usr/local/etc
sudo wget -qO /usr/local/etc/YSFHosts.txt https://www.pistar.uk/downloads/YSFHosts.txt || \
sudo wget -qO /usr/local/etc/YSFHosts.txt https://dvref.com/YSFHosts.txt
```

---

## Phase 9: WiFi Auto AP Fallback (Ultra Light Version)

The script is intentionally very simple to avoid previous freeze issues.

```bash
sudo cp ~/scripts/wifi-fallback-light.sh /usr/local/bin/cyberfusion-wifi-fallback
sudo chmod +x /usr/local/bin/cyberfusion-wifi-fallback

sudo cp ~/systemd/cyberfusion-wifi-fallback.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cyberfusion-wifi-fallback
```

Copy the hostapd and dnsmasq configs:

```bash
sudo cp ~/configs/hostapd.conf /etc/hostapd/hostapd.conf
sudo mkdir -p /etc/dnsmasq.d
sudo cp ~/configs/dnsmasq.conf /etc/dnsmasq.d/cyberfusion.conf
```

**Note on SSID**: Default `CyberFusion-Hotspot`. Edit `/etc/hostapd/hostapd.conf` if you want to change password or make it open.

Reboot after this or start the service manually later.

---

## Phase 10: Dashboard (Pure stdlib Python — very light)

No pip, no venv, no Flask.

```bash
sudo mkdir -p /opt/cyberfusion-dashboard/static
sudo cp ~/dashboard/cyberfusion-dash.py /opt/cyberfusion-dashboard/
sudo cp -r ~/dashboard/static/* /opt/cyberfusion-dashboard/static/
sudo chown -R pi:pi /opt/cyberfusion-dashboard
```

Install the service:

```bash
sudo cp ~/systemd/cyberfusion-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cyberfusion-dashboard
```

The dashboard listens on port 80 (or change to 8080 in the unit if you prefer non-root).

---

## Phase 11: Systemd Services for MMDVM + YSF

```bash
sudo cp ~/systemd/mmdvmhost.service /etc/systemd/system/
sudo cp ~/systemd/ysfgateway.service /etc/systemd/system/

sudo systemctl daemon-reload

sudo systemctl enable mmdvmhost ysfgateway cyberfusion-dashboard
```

Start them (one at a time):

```bash
sudo systemctl start ysfgateway
sudo systemctl start mmdvmhost
sudo systemctl start cyberfusion-dashboard
```

Check:

```bash
sudo systemctl status --no-pager ysfgateway mmdvmhost
journalctl -u ysfgateway -n 30 --no-pager
```

---

## Phase 12: Final Reboot & Test

```bash
sudo reboot
```

After reboot:

- `ping cyberfusion-hotspot.local` from phone/laptop
- Open http://cyberfusion-hotspot.local (or the IP, or 192.168.50.1 when in AP mode)
- Use the big neon buttons.
- Check Nextion (if connected) shows status.
- Use `tailscale` for remote when away.

---

## MMDVM Hotspot Board v1.5.2 Specific Notes (Pi Zero)

- The board usually stacks directly on the Pi GPIO header.
- Communication is typically over the primary UART: **`/dev/ttyAMA0`** or the symlink **`/dev/serial0`**.
- After the raspi-config serial step above, MMDVMHost should see it.
- Common first settings in mmdvmhost.ini `[Modem]`:
  - `Port=/dev/ttyAMA0`
  - Start with `RXOffset=0`, `TXOffset=0`, `RXLevel=50`, `TXLevel=50`
  - Use `MMDVMCal` (if you build it) or adjust by ear / with a service monitor.
- Power: Use a strong 5V supply. The board + PA can draw significant current on transmit.
- Antenna: UHF (or VHF) as per your board version. Keep short jumper leads if any.
- For Nextion 2.4": Use a USB-to-TTL adapter (cheapest/safest on Pi Zero). Connect TX/RX crossed, 5V/GND. Set the port in the `[Nextion]` section of mmdvmhost.ini.

Test the port with `screen /dev/ttyAMA0 115200` (should see garbage or nothing until MMDVMHost runs).

---

## Troubleshooting Light Steps

- No RF: Check `journalctl -u mmdvmhost`, modem port setting, levels.
- Can't change rooms from dashboard: Check the ysf-* scripts are in PATH and sudoers is correct. Test manually: `sudo ysf-link YSF23453`
- AP not coming up: Run `/usr/local/bin/cyberfusion-wifi-fallback force-ap` by hand and watch output.
- Dashboard not loading: `sudo systemctl status cyberfusion-dashboard`, check port 80 not conflicted.
- Memory pressure on Zero: Only run one service check at a time. Use `tmux`.

---

## Files You Need from the Pi 5 cyberfusion-pi-zero Directory

- `configs/`
- `scripts/` (especially the step helpers and control scripts)
- `dashboard/`
- `systemd/`
- `binaries/` (the two executables — copy these if pre-built)

---

## After It Works

- Update YSFHosts weekly with a cron (example in docs).
- Calibrate frequency/levels properly.
- Add more rooms to the dashboard HTML if desired (easy 4-button grid).

Enjoy the truck. Clean. Stable. Neon.

73
