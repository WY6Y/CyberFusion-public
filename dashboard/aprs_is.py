#!/usr/bin/env python3
"""
CyberFusion mobile APRS-IS helper (pure stdlib).

- Long-lived TCP connection to APRS-IS for RX (nearby) + TX (position beacon)
- Phone supplies GPS via dashboard API; Pi has no GPS unit
- IS-only (TCPIP* path) — not an RF digi; keep its SSID distinct from any
  RF digi/WX station you run
"""

from __future__ import annotations

import logging
import math
import os
import re
import socket
import threading
import time

logger = logging.getLogger("cyberfusion.aprs")

RECONNECT_BASE = 5
RECONNECT_MAX = 60
SOCKET_TIMEOUT = 120
STATION_STALE_SEC = 2 * 3600
GPS_STALE_SEC = 90
FILTER_MOVE_M = 2000  # re-send #filter after this much movement
DEFAULT_RANGE_KM = 50

# Uncompressed position after data-type ID (! = / @)
_POS_RE = re.compile(
    r"^(?P<lat>\d{2})(?P<lat_mm>\d{2}\.\d{2})(?P<lat_h>[NS])"
    r"(?P<table>[/\\])"
    r"(?P<lon>\d{3})(?P<lon_mm>\d{2}\.\d{2})(?P<lon_h>[EW])"
    r"(?P<symbol>.)"
    r"(?P<rest>.*)$"
)
_CSE_SPD_RE = re.compile(r"^(?P<cse>\d{3})/(?P<spd>\d{3})(?P<comment>.*)$")
_CALL_RE = re.compile(r"^[A-Z0-9]{1,7}(?:-[0-9]{1,2})?$")
_FRAME_RE = re.compile(
    r"^(?P<source>[A-Za-z0-9\-]+)>(?P<dest>[A-Za-z0-9\-]+)"
    r"(?P<path>(?:,[A-Za-z0-9\-*]+)*):(?P<body>.*)$"
)


def aprs_passcode(callsign: str) -> int:
    cs = callsign.split("-")[0].upper()
    h = 0x73E2
    for i in range(0, len(cs), 2):
        h ^= ord(cs[i]) << 8
        if i + 1 < len(cs):
            h ^= ord(cs[i + 1])
    return h & 0x7FFF


def deg_to_aprs_lat(lat: float) -> str:
    hemi = "N" if lat >= 0 else "S"
    lat = abs(lat)
    deg = int(lat)
    minutes = (lat - deg) * 60.0
    return f"{deg:02d}{minutes:05.2f}{hemi}"


def deg_to_aprs_lon(lon: float) -> str:
    hemi = "E" if lon >= 0 else "W"
    lon = abs(lon)
    deg = int(lon)
    minutes = (lon - deg) * 60.0
    return f"{deg:03d}{minutes:05.2f}{hemi}"


def aprs_lat_to_deg(dd: str, mm: str, hemi: str) -> float:
    val = int(dd) + float(mm) / 60.0
    return val if hemi.upper() == "N" else -val


def aprs_lon_to_deg(ddd: str, mm: str, hemi: str) -> float:
    val = int(ddd) + float(mm) / 60.0
    return val if hemi.upper() == "E" else -val


def clean_ascii(s: str, max_len: int = 43) -> str:
    s = "".join(ch for ch in (s or "") if 32 <= ord(ch) < 127)
    return s.strip()[:max_len]


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    return haversine_km(lat1, lon1, lat2, lon2) * 1000.0


def mps_to_knots(mps: float) -> int:
    try:
        return max(0, min(999, int(round(float(mps) * 1.943844))))
    except (TypeError, ValueError):
        return 0


def validate_callsign(cs: str) -> str | None:
    cs = (cs or "").strip().upper()
    if not cs or not _CALL_RE.match(cs):
        return None
    return cs


def build_position_info(
    lat: float,
    lon: float,
    comment: str = "",
    freq_mhz: str = "",
    course: float | None = None,
    speed_mps: float | None = None,
    symbol_table: str = "/",
    symbol: str = ">",
) -> str:
    """Uncompressed APRS position info field (no callsign header)."""
    lat_s = deg_to_aprs_lat(lat)
    lon_s = deg_to_aprs_lon(lon)
    st = symbol_table if symbol_table in ("/", "\\") else "/"
    sy = (symbol or ">")[0]
    body = f"!{lat_s}{st}{lon_s}{sy}"

    ext = ""
    if course is not None and speed_mps is not None:
        try:
            cse = int(round(float(course))) % 360
            if cse == 0:
                cse = 360
            spd = mps_to_knots(speed_mps)
            ext = f"{cse:03d}/{spd:03d}"
        except (TypeError, ValueError):
            ext = ""

    parts = []
    fm = clean_ascii(str(freq_mhz or ""), 12)
    if fm:
        if not fm.upper().endswith("MHZ"):
            fm = f"{fm}MHz"
        parts.append(fm)
    cm = clean_ascii(comment, 43)
    if cm:
        parts.append(cm)
    cmt = clean_ascii(" ".join(parts), 43)
    return body + ext + cmt


def build_tnc2(callsign: str, info: str, tocall: str = "APCF01") -> str:
    return f"{callsign}>{tocall},TCPIP*:{info}"


def parse_uncompressed_body(body: str) -> dict | None:
    """Parse position from info field (may include data-type ID prefix)."""
    if not body:
        return None
    raw = body
    # Strip data type / timestamp prefixes
    if raw[0] in ("!", "="):
        raw = raw[1:]
    elif raw[0] in ("/", "@") and len(raw) > 8:
        # /HHMMSSz or @HHMMSSh timestamp (7 chars) then lat...
        raw = raw[8:]
    elif raw[0] == ";":  # object — skip for v1
        return None
    elif raw[0] == ")":  # item — skip
        return None

    m = _POS_RE.match(raw)
    if not m:
        return None
    try:
        lat = aprs_lat_to_deg(m.group("lat"), m.group("lat_mm"), m.group("lat_h"))
        lon = aprs_lon_to_deg(m.group("lon"), m.group("lon_mm"), m.group("lon_h"))
    except ValueError:
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None

    rest = m.group("rest") or ""
    course = speed = None
    comment = rest
    cm = _CSE_SPD_RE.match(rest)
    if cm:
        try:
            course = int(cm.group("cse"))
            if course == 360:
                course = 0
            speed = int(cm.group("spd"))  # knots
            comment = cm.group("comment") or ""
        except ValueError:
            pass

    return {
        "lat": lat,
        "lon": lon,
        "symbol_table": m.group("table"),
        "symbol": m.group("symbol"),
        "course": course,
        "speed": speed,
        "comment": clean_ascii(comment, 80),
        "packet_format": "uncompressed",
    }


def parse_mice(dstcall: str, body: str) -> dict | None:
    """
    Minimal Mic-E decoder (most mobile trackers). Pure stdlib.
    Algorithm aligned with APRS 1.01 ch.10 / aprslib parse_mice (no telemetry).
    `body` is the full info field including leading ` or '.
    Speed returned in knots for consistency with uncompressed parse.
    """
    if not body or body[0] not in ("`", "'"):
        return None
    # aprslib-style payload is AFTER the datatype ID
    data = body[1:]
    dst = (dstcall or "").split("-")[0].upper()
    if len(dst) != 6 or len(data) < 8:
        return None
    if not re.match(r"^[0-9A-Z]{3}[0-9L-Z]{3}$", dst):
        return None

    # Destination → latitude digits (spaces for KLZ)
    tmp = []
    for ch in dst:
        if ch in "KLZ":
            tmp.append(" ")
        elif ord(ch) > 76:  # P-Y
            tmp.append(chr(ord(ch) - 32))
        elif ord(ch) > 57:  # A-J
            tmp.append(chr(ord(ch) - 17))
        else:
            tmp.append(ch)
    tmp_s = "".join(tmp)
    mamb = re.match(r"^(\d+)( *)$", tmp_s)
    if not mamb:
        return None
    posambiguity = len(mamb.group(2))
    chars = list(tmp_s)
    if posambiguity > 0:
        if posambiguity >= 4:
            chars[2] = "3"
        else:
            chars[6 - posambiguity] = "5"
    tmp_s = "".join(chars).replace(" ", "0")
    try:
        latminutes = float(f"{tmp_s[2:4]}.{tmp_s[4:6]}")
        latitude = int(tmp_s[0:2]) + (latminutes / 60.0)
    except ValueError:
        return None
    if ord(dst[3]) <= 0x4C:  # S
        latitude = -latitude

    # Longitude degrees / minutes from info field
    longitude = ord(data[0]) - 28
    if ord(dst[4]) >= 0x50:  # +100 offset
        longitude += 100
    if 180 <= longitude <= 189:
        longitude -= 80
    if 190 <= longitude <= 199:
        longitude -= 190
    lngminutes = float(ord(data[1]) - 28)
    if lngminutes >= 60:
        lngminutes -= 60
    lngminutes += (ord(data[2]) - 28.0) / 100.0
    if posambiguity == 4:
        lngminutes = 30.0
    elif posambiguity == 3:
        lngminutes = (math.floor(lngminutes / 10) + 0.5) * 10
    elif posambiguity == 2:
        lngminutes = math.floor(lngminutes) + 0.5
    elif posambiguity == 1:
        lngminutes = (math.floor(lngminutes * 10) + 0.5) / 10.0
    longitude += lngminutes / 60.0
    if ord(dst[5]) >= 0x50:  # W
        longitude = -longitude

    # Speed (knots) and course
    sp = (ord(data[3]) - 28) * 10
    dc = ord(data[4]) - 28
    quot = int(dc / 10.0)
    dc = dc - quot * 10
    course = dc * 100 + (ord(data[5]) - 28)
    sp = sp + quot
    if sp >= 800:
        sp -= 800
    if course >= 400:
        course -= 400
    speed_kn = sp  # already knots in Mic-E encoding

    symbol = data[6]
    symbol_table = data[7]
    comment = clean_ascii(data[8:], 80) if len(data) > 8 else ""

    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return None

    return {
        "lat": latitude,
        "lon": longitude,
        "symbol_table": symbol_table,
        "symbol": symbol,
        "course": course if course != 0 or speed_kn else None,
        "speed": speed_kn,
        "comment": comment,
        "packet_format": "mic-e",
    }


def parse_tnc2_line(text: str) -> dict | None:
    text = text.strip()
    if not text or text.startswith("#"):
        return None
    m = _FRAME_RE.match(text)
    if not m:
        return None
    source = m.group("source").upper()
    dest = (m.group("dest") or "").upper()
    body = m.group("body") or ""
    # Third-party } frames — skip nested complexity in v1
    if body.startswith("}"):
        return None

    pos = None
    if body and body[0] in ("`", "'"):
        pos = parse_mice(dest, body)
    if not pos:
        pos = parse_uncompressed_body(body)
    if not pos:
        return None
    pos["callsign"] = source
    pos["raw"] = text[:200]
    return pos


class StationStore:
    def __init__(self, stale_sec: int = STATION_STALE_SEC):
        self._lock = threading.Lock()
        self._stations = {}
        self.stale_sec = stale_sec

    def update(self, callsign, lat, lon, **kwargs):
        if not callsign:
            return
        callsign = str(callsign).upper()
        with self._lock:
            prev = self._stations.get(callsign, {})
            self._stations[callsign] = {
                "callsign": callsign,
                "lat": lat,
                "lon": lon,
                "symbol": kwargs.get("symbol", prev.get("symbol")),
                "symbol_table": kwargs.get("symbol_table", prev.get("symbol_table")),
                "comment": kwargs.get("comment", prev.get("comment")),
                "course": kwargs.get("course", prev.get("course")),
                "speed": kwargs.get("speed", prev.get("speed")),
                "packet_format": kwargs.get("packet_format", prev.get("packet_format")),
                "last_heard": time.time(),
                "source": kwargs.get("source", "is"),
            }

    def nearby(self, lat: float | None, lon: float | None, range_km: float, limit: int = 80):
        cutoff = time.time() - self.stale_sec
        with self._lock:
            items = [dict(s) for s in self._stations.values() if s["last_heard"] >= cutoff]
        out = []
        for s in items:
            if lat is None or lon is None:
                s["distance_km"] = None
                out.append(s)
                continue
            d = haversine_km(lat, lon, s["lat"], s["lon"])
            if d <= range_km * 1.5:
                s["distance_km"] = round(d, 2)
                s["age_sec"] = int(time.time() - s["last_heard"])
                out.append(s)
        out.sort(key=lambda x: (x.get("distance_km") is None, x.get("distance_km") or 0))
        return out[:limit]

    def count(self) -> int:
        with self._lock:
            return len(self._stations)


class AprsIsService:
    """Background APRS-IS client for CyberFusion mobile beacon + nearby RX."""

    def __init__(self):
        self.host = os.environ.get("APRSIS_HOST", "noam.aprs2.net")
        self.port = int(os.environ.get("APRSIS_PORT", "14580"))
        self.callsign = validate_callsign(os.environ.get("APRS_CALLSIGN", "N0CALL-9")) or "N0CALL-9"
        pass_env = os.environ.get("APRS_PASSCODE", "").strip()
        self.passcode = int(pass_env) if pass_env else aprs_passcode(self.callsign)
        self.tocall = os.environ.get("APRS_TOCALL", "APCF01")
        self.range_km = float(os.environ.get("APRS_RANGE_KM", str(DEFAULT_RANGE_KM)))
        self.comment = clean_ascii(os.environ.get("APRS_COMMENT", "CyberFusion mobile"), 40)
        self.freq = clean_ascii(os.environ.get("APRS_DEFAULT_FREQ", "146.520"), 12)
        self.symbol_table = os.environ.get("APRS_SYMBOL_TABLE", "/")[:1] or "/"
        self.symbol = os.environ.get("APRS_SYMBOL", ">")[:1] or ">"
        self.beacon_min_sec = int(os.environ.get("APRS_BEACON_MIN_SEC", "60"))
        self.beacon_max_sec = int(os.environ.get("APRS_BEACON_MAX_SEC", "600"))
        self.move_m = float(os.environ.get("APRS_MOVE_M", "200"))
        self.gps_stale_sec = int(os.environ.get("APRS_GPS_STALE_SEC", str(GPS_STALE_SEC)))

        self.store = StationStore()
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._sock = None
        self._sock_lock = threading.Lock()

        self.beacon_on = False
        self.connected = False
        self.connected_since = None
        self.login_verified = None  # True/False/None
        self.last_error = None
        self.last_line_at = None
        self.line_count = 0
        self.station_update_count = 0
        self.reconnect_count = 0
        self.tx_count = 0
        self.last_tx_at = None
        self.last_tx_packet = None
        self.unparsed_count = 0

        # Phone GPS
        self.gps_lat = None
        self.gps_lon = None
        self.gps_accuracy = None
        self.gps_course = None
        self.gps_speed_mps = None
        self.gps_at = None

        self._last_beacon_lat = None
        self._last_beacon_lon = None
        self._last_beacon_at = 0.0
        self._filter_lat = None
        self._filter_lon = None
        self._pending_force = False

        self._started = False

    def start(self):
        if self._started:
            return
        self._started = True
        threading.Thread(target=self._run_forever, daemon=True, name="aprs-is").start()
        threading.Thread(target=self._beacon_loop, daemon=True, name="aprs-beacon").start()
        logger.info(
            "APRS-IS service started callsign=%s host=%s:%s range=%skm",
            self.callsign,
            self.host,
            self.port,
            self.range_km,
        )

    def stop(self):
        self._stop.set()
        with self._sock_lock:
            if self._sock:
                try:
                    self._sock.close()
                except Exception:
                    pass
                self._sock = None

    # --- public API used by dashboard ---

    def status(self) -> dict:
        with self._lock:
            gps_age = (time.time() - self.gps_at) if self.gps_at else None
            last_tx_age = (time.time() - self.last_tx_at) if self.last_tx_at else None
            return {
                "beacon_on": self.beacon_on,
                "is_connected": self.connected,
                "login_verified": self.login_verified,
                "callsign": self.callsign,
                "freq": self.freq,
                "comment": self.comment,
                "range_km": self.range_km,
                "symbol": f"{self.symbol_table}{self.symbol}",
                "gps": {
                    "lat": self.gps_lat,
                    "lon": self.gps_lon,
                    "accuracy": self.gps_accuracy,
                    "course": self.gps_course,
                    "speed_mps": self.gps_speed_mps,
                    "age_sec": round(gps_age, 1) if gps_age is not None else None,
                    "stale": bool(gps_age is None or gps_age > self.gps_stale_sec),
                },
                "last_tx_age_sec": round(last_tx_age, 1) if last_tx_age is not None else None,
                "last_tx_packet": self.last_tx_packet,
                "tx_count": self.tx_count,
                "station_count": self.store.count(),
                "line_count": self.line_count,
                "unparsed_count": self.unparsed_count,
                "reconnect_count": self.reconnect_count,
                "last_error": self.last_error,
                "host": f"{self.host}:{self.port}",
                "gps_stale_sec": self.gps_stale_sec,
                "beacon_min_sec": self.beacon_min_sec,
                "beacon_max_sec": self.beacon_max_sec,
            }

    def set_position(
        self,
        lat: float,
        lon: float,
        accuracy: float | None = None,
        course: float | None = None,
        speed_mps: float | None = None,
    ) -> dict:
        try:
            lat = float(lat)
            lon = float(lon)
        except (TypeError, ValueError):
            return {"ok": False, "error": "invalid lat/lon"}
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return {"ok": False, "error": "lat/lon out of range"}

        with self._lock:
            self.gps_lat = lat
            self.gps_lon = lon
            self.gps_accuracy = float(accuracy) if accuracy is not None else None
            self.gps_course = float(course) if course is not None else None
            self.gps_speed_mps = float(speed_mps) if speed_mps is not None else None
            self.gps_at = time.time()
            next_in = self._seconds_until_next_beacon_locked()

        self._maybe_update_filter(lat, lon)
        return {"ok": True, "next_beacon_in": next_in}

    def control(self, data: dict) -> dict:
        with self._lock:
            if "beacon" in data:
                v = data["beacon"]
                if isinstance(v, bool):
                    self.beacon_on = v
                elif str(v).lower() in ("on", "1", "true", "yes"):
                    self.beacon_on = True
                elif str(v).lower() in ("off", "0", "false", "no"):
                    self.beacon_on = False
            if data.get("freq") is not None:
                self.freq = clean_ascii(str(data["freq"]), 12)
            if data.get("comment") is not None:
                self.comment = clean_ascii(str(data["comment"]), 40)
            if data.get("range_km") is not None:
                try:
                    self.range_km = max(5.0, min(500.0, float(data["range_km"])))
                except (TypeError, ValueError):
                    pass
            if data.get("callsign"):
                cs = validate_callsign(data["callsign"])
                if not cs:
                    return {"ok": False, "error": "invalid callsign"}
                old = self.callsign
                self.callsign = cs
                if not os.environ.get("APRS_PASSCODE", "").strip():
                    self.passcode = aprs_passcode(cs)
                if cs != old:
                    # Force reconnect with new callsign
                    self._kick_socket()
            if data.get("symbol") and len(str(data["symbol"])) >= 1:
                sy = str(data["symbol"])
                if len(sy) >= 2 and sy[0] in ("/", "\\"):
                    self.symbol_table = sy[0]
                    self.symbol = sy[1]
                else:
                    self.symbol = sy[0]
        # Refresh filter if range changed
        with self._lock:
            lat, lon = self.gps_lat, self.gps_lon
            rk = self.range_km
        if lat is not None and lon is not None:
            self._send_filter(lat, lon, rk, force=True)
        return {"ok": True, **self.status()}

    def force_beacon(self) -> dict:
        with self._lock:
            if self.gps_lat is None or self.gps_lon is None:
                return {"ok": False, "error": "no GPS fix yet"}
            age = time.time() - (self.gps_at or 0)
            if age > self.gps_stale_sec:
                return {"ok": False, "error": "GPS stale — keep phone tab open"}
            self._pending_force = True
        ok, msg = self._try_beacon(force=True)
        return {"ok": ok, "message": msg, **self.status()}

    def nearby(self) -> list:
        with self._lock:
            lat, lon, rk = self.gps_lat, self.gps_lon, self.range_km
            own = self.callsign
        stations = self.store.nearby(lat, lon, rk)
        # Prefer not listing ourselves if we inject back via filter (usually not)
        return [s for s in stations if s.get("callsign") != own]

    # --- internal ---

    def _kick_socket(self):
        with self._sock_lock:
            if self._sock:
                try:
                    self._sock.close()
                except Exception:
                    pass
                self._sock = None

    def _seconds_until_next_beacon_locked(self) -> float | None:
        if not self.beacon_on:
            return None
        if self.gps_lat is None:
            return None
        if not self._last_beacon_at:
            return 0.0
        interval = self._desired_interval_locked()
        rem = interval - (time.time() - self._last_beacon_at)
        return max(0.0, round(rem, 1))

    def _desired_interval_locked(self) -> float:
        """Adaptive interval: short when moving, long when still."""
        if self._last_beacon_lat is None or self.gps_lat is None:
            return float(self.beacon_min_sec)
        dist = haversine_m(
            self._last_beacon_lat, self._last_beacon_lon, self.gps_lat, self.gps_lon
        )
        spd = self.gps_speed_mps or 0.0
        if dist >= self.move_m or spd >= 1.5:  # ~3 kn
            return float(self.beacon_min_sec)
        return float(self.beacon_max_sec)

    def _beacon_loop(self):
        while not self._stop.is_set():
            try:
                force = False
                with self._lock:
                    if self._pending_force:
                        force = True
                        self._pending_force = False
                if force or self._should_beacon():
                    self._try_beacon(force=force)
            except Exception as exc:
                logger.warning("beacon loop error: %s", exc)
                self.last_error = str(exc)
            self._stop.wait(2.0)

    def _should_beacon(self) -> bool:
        with self._lock:
            if not self.beacon_on:
                return False
            if self.gps_lat is None or self.gps_lon is None or not self.gps_at:
                return False
            if time.time() - self.gps_at > self.gps_stale_sec:
                return False
            if not self._last_beacon_at:
                return True
            interval = self._desired_interval_locked()
            if time.time() - self._last_beacon_at >= interval:
                return True
            # Significant move since last TX
            if self._last_beacon_lat is not None:
                d = haversine_m(
                    self._last_beacon_lat,
                    self._last_beacon_lon,
                    self.gps_lat,
                    self.gps_lon,
                )
                if d >= self.move_m and (time.time() - self._last_beacon_at) >= self.beacon_min_sec:
                    return True
            return False

    def _try_beacon(self, force: bool = False) -> tuple[bool, str]:
        with self._lock:
            if self.gps_lat is None or self.gps_lon is None:
                return False, "no GPS"
            age = time.time() - (self.gps_at or 0)
            if age > self.gps_stale_sec and not force:
                return False, "GPS stale"
            lat = self.gps_lat
            lon = self.gps_lon
            course = self.gps_course
            speed = self.gps_speed_mps
            comment = self.comment
            freq = self.freq
            callsign = self.callsign
            tocall = self.tocall
            st, sy = self.symbol_table, self.symbol

        info = build_position_info(
            lat,
            lon,
            comment=comment,
            freq_mhz=freq,
            course=course,
            speed_mps=speed,
            symbol_table=st,
            symbol=sy,
        )
        tnc2 = build_tnc2(callsign, info, tocall=tocall)
        ok = self._send_packet(tnc2)
        if ok:
            with self._lock:
                self.tx_count += 1
                self.last_tx_at = time.time()
                self.last_tx_packet = tnc2
                self._last_beacon_at = time.time()
                self._last_beacon_lat = lat
                self._last_beacon_lon = lon
            logger.info("APRS-IS TX: %s", tnc2)
            return True, "sent"
        return False, self.last_error or "send failed"

    def _send_packet(self, tnc2: str) -> bool:
        line = tnc2 if tnc2.endswith("\r\n") else tnc2 + "\r\n"
        with self._sock_lock:
            sock = self._sock
            if not sock or not self.connected:
                self.last_error = "not connected to APRS-IS"
                return False
            try:
                sock.sendall(line.encode("ascii", errors="replace"))
                return True
            except Exception as exc:
                self.last_error = str(exc)
                try:
                    sock.close()
                except Exception:
                    pass
                self._sock = None
                self.connected = False
                return False

    def _maybe_update_filter(self, lat: float, lon: float):
        with self._lock:
            fl, fo, rk = self._filter_lat, self._filter_lon, self.range_km
        if fl is None or fo is None:
            self._send_filter(lat, lon, rk, force=True)
            return
        if haversine_m(fl, fo, lat, lon) >= FILTER_MOVE_M:
            self._send_filter(lat, lon, rk, force=True)

    def _send_filter(self, lat: float, lon: float, range_km: float, force: bool = False):
        cmd = f"#filter r/{lat:.4f}/{lon:.4f}/{range_km:.0f}\r\n"
        with self._sock_lock:
            sock = self._sock
            if not sock or not self.connected:
                return
            try:
                sock.sendall(cmd.encode("ascii"))
                with self._lock:
                    self._filter_lat = lat
                    self._filter_lon = lon
                logger.info("APRS-IS filter updated %s", cmd.strip())
            except Exception as exc:
                logger.debug("filter send failed: %s", exc)

    def _run_forever(self):
        delay = RECONNECT_BASE
        while not self._stop.is_set():
            try:
                self._connect_and_read()
                delay = RECONNECT_BASE
            except Exception as exc:
                self.last_error = str(exc)
                logger.warning("APRS-IS connection lost/failed: %s", exc)
            self.connected = False
            self.connected_since = None
            with self._sock_lock:
                self._sock = None
            if self._stop.is_set():
                return
            self.reconnect_count += 1
            time.sleep(delay)
            delay = min(delay * 1.5, RECONNECT_MAX)

    def _connect_and_read(self):
        with self._lock:
            lat = self.gps_lat
            lon = self.gps_lon
            rk = self.range_km
            callsign = self.callsign
            passcode = self.passcode

        # Bootstrap filter near last fix, else mid-US default until GPS arrives
        if lat is None or lon is None:
            lat, lon = 39.83, -98.58

        sock = socket.create_connection((self.host, self.port), timeout=15)
        sock.settimeout(SOCKET_TIMEOUT)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        if hasattr(socket, "TCP_KEEPIDLE"):
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 60)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 4)

        filt = f"r/{lat:.4f}/{lon:.4f}/{rk:.0f}"
        login = f"user {callsign} pass {passcode} vers CyberFusion 1.0 filter {filt}\r\n"
        sock.sendall(login.encode("ascii"))

        with self._sock_lock:
            self._sock = sock
        self.connected = True
        self.connected_since = time.time()
        self.login_verified = None
        with self._lock:
            self._filter_lat = lat
            self._filter_lon = lon
        logger.info("Connected to APRS-IS %s:%s as %s filter=%s", self.host, self.port, callsign, filt)

        buf = b""
        try:
            while not self._stop.is_set():
                try:
                    data = sock.recv(4096)
                except socket.timeout:
                    continue
                if not data:
                    raise ConnectionError("APRS-IS closed connection")
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    line = line.strip(b"\r")
                    if line:
                        self._handle_line(line)
        finally:
            try:
                sock.close()
            except Exception:
                pass

    def _handle_line(self, raw: bytes):
        self.line_count += 1
        self.last_line_at = time.time()
        if raw.startswith(b"#"):
            text = raw.decode("utf-8", errors="replace")
            low = text.lower()
            if "logresp" in low:
                if "unverified" in low:
                    self.login_verified = False
                    self.last_error = "APRS-IS login unverified — check passcode"
                    logger.error("%s", text.strip()[:160])
                elif "verified" in low:
                    self.login_verified = True
                    logger.info("%s", text.strip()[:160])
            return

        try:
            text = raw.decode("utf-8", errors="replace")
        except Exception:
            return

        parsed = parse_tnc2_line(text)
        if not parsed:
            self.unparsed_count += 1
            return

        self.store.update(
            parsed["callsign"],
            parsed["lat"],
            parsed["lon"],
            symbol=parsed.get("symbol"),
            symbol_table=parsed.get("symbol_table"),
            comment=parsed.get("comment"),
            course=parsed.get("course"),
            speed=parsed.get("speed"),
            packet_format=parsed.get("packet_format"),
            source="is",
        )
        self.station_update_count += 1


# Singleton used by dashboard
_service: AprsIsService | None = None
_service_lock = threading.Lock()


def get_service() -> AprsIsService:
    global _service
    with _service_lock:
        if _service is None:
            _service = AprsIsService()
            _service.start()
        return _service
