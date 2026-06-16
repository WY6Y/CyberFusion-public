#!/usr/bin/env python3
"""Generate 320x240 CyberFusion Nextion background PNGs (NX3224T024)."""
from PIL import Image, ImageDraw, ImageFont
import os

W, H = 320, 240
BG = (5, 5, 5)
CYAN = (0, 240, 255)
GREEN = (0, 255, 159)
MAGENTA = (255, 0, 170)
DIM = (40, 40, 48)
GRID = (0, 240, 255, 18)

OUT = os.path.join(os.path.dirname(__file__), "assets")


def grid(draw):
    for x in range(0, W, 32):
        draw.line([(x, 0), (x, H)], fill=GRID, width=1)
    for y in range(0, H, 32):
        draw.line([(0, y), (W, y)], fill=GRID, width=1)


def font(size):
    for name in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
    ):
        if os.path.isfile(name):
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def hud_box(draw, xy, wh):
    x, y = xy
    ww, hh = wh
    draw.rectangle([x, y, x + ww, y + hh], outline=CYAN, width=1)
    draw.rectangle([x + 1, y + 1, x + ww - 1, y + hh - 1], outline=(0, 60, 70), width=1)


def header(draw, title, subtitle):
    f_title = font(22)
    f_sub = font(10)
    draw.text((8, 6), title, fill=CYAN, font=f_title)
    draw.line([(8, 32), (W - 8, 32)], fill=(0, 240, 255, 80), width=1)
    draw.text((8, 36), subtitle, fill=GREEN, font=f_sub)


def scanlines(img):
    px = img.load()
    for y in range(0, H, 4):
        for x in range(W):
            r, g, b = px[x, y]
            px[x, y] = (max(0, r - 6), max(0, g - 6), max(0, b - 6))


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path, "PNG")
    print(path)


def page_mmdvm():
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    grid(draw)
    header(draw, "CYBERFUSION HOTSPOT", "YSF · SIMPLEX · SET YOUR MHz")
    hud_box(draw, (8, 52), (304, 178))
    draw.text((16, 58), "STATUS", fill=GREEN, font=font(9))
    draw.text((16, 78), "CALL / ID", fill=(120, 120, 120), font=font(8))
    draw.text((16, 118), "CLOCK", fill=(120, 120, 120), font=font(8))
    draw.text((16, 158), "IP / LOCATION", fill=(120, 120, 120), font=font(8))
    draw.text((200, 58), "CPU", fill=(120, 120, 120), font=font(8))
    draw.text((200, 100), "RX MHz", fill=(120, 120, 120), font=font(8))
    draw.text((200, 142), "TX MHz", fill=(120, 120, 120), font=font(8))
    draw.rectangle([0, H - 14, W, H], fill=(10, 10, 14))
    draw.text((8, H - 12), "MMDVM IDLE", fill=MAGENTA, font=font(9))
    scanlines(img)
    save(img, "bg_mmdvm.png")


def page_mode(name, band):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    grid(draw)
    header(draw, "CYBERFUSION HOTSPOT", f"{name} · {band}")
    hud_box(draw, (8, 52), (304, 100))
    draw.text((16, 60), "SOURCE", fill=GREEN, font=font(9))
    draw.text((16, 100), "DEST / DG-ID", fill=(120, 120, 120), font=font(8))
    hud_box(draw, (8, 158), (304, 74))
    draw.text((16, 166), "ORIGIN / REFLECTOR", fill=(120, 120, 120), font=font(8))
    draw.text((200, 190), "RSSI", fill=(120, 120, 120), font=font(8))
    draw.text((260, 190), "BER", fill=(120, 120, 120), font=font(8))
    scanlines(img)
    save(img, f"bg_{band.lower()}.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    page_mmdvm()
    page_mode("SYSTEM FUSION", "YSF")
    page_mode("D-STAR", "DSTAR")
    page_mode("DMR", "DMR")
    page_mode("P25", "P25")
    page_mode("NXDN", "NXDN")


if __name__ == "__main__":
    main()