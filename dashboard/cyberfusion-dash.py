#!/usr/bin/env python3
"""
WY6Y CyberFusion Dashboard - pure stdlib (no Flask, no pip, no venv)
Lightweight for Pi Zero. Serves HTML/JS/CSS + simple API endpoints
that call the ysf-* sudo scripts.
Run as: python3 cyberfusion-dash.py
"""
import http.server
import socketserver
import subprocess
import json
import os
import re
import threading
import time
from collections import deque
from datetime import datetime, timezone

PORT = int(os.environ.get("PORT", "80"))
DASH_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(DASH_DIR, "static")
LOCAL_CALLSIGN = os.environ.get("LOCAL_CALLSIGN", "WY6Y")

# Simple in-memory last link
LAST = ""

TRAFFIC_LOCK = threading.Lock()
TRAFFIC = {
    "active": None,
    "recent": deque(maxlen=30),
}

_LOG_TS = re.compile(r"^[DIWM]:\s*([\d-]+\s+[\d:.]+)")

_TRAFFIC_PATTERNS = {
    "rf_header": re.compile(
        r"YSF, received RF header from (.+?) to DG-ID (\d+)"
    ),
    "rf_late": re.compile(
        r"YSF, received RF late entry from (.+?) to DG-ID (\d+)"
    ),
    "rf_end": re.compile(
        r"YSF, received RF end of transmission from (.+?) to DG-ID (\d+), ([\d.]+) seconds"
    ),
    "net_data": re.compile(
        r"YSF, received network data from (.+?) to DG-ID (\d+) at (.+?)\s*$"
    ),
    "net_end": re.compile(
        r"YSF, received network end of transmission from (.+?) to DG-ID (\d+) at (.+?), ([\d.]+) seconds"
    ),
}


def _clean_callsign(value):
    return re.sub(r"-ND$", "", value.strip())


def _is_local(callsign):
    base = _clean_callsign(callsign)
    local = _clean_callsign(LOCAL_CALLSIGN)
    return base == local


def _now_iso():
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _traffic_entry(kind, callsign, dgid="0", dest="", duration=None, ended=False, log_time=None):
    entry = {
        "callsign": callsign,
        "kind": kind,
        "dgid": int(dgid) if str(dgid).isdigit() else 0,
        "dest": dest.strip() if dest else "",
        "local": _is_local(callsign),
        "time": log_time or _now_iso(),
    }
    if duration is not None:
        entry["duration"] = float(duration)
    if ended:
        entry["ended"] = True
    return entry


def _set_active(entry):
    TRAFFIC["active"] = entry


def _clear_active(callsign, kind):
    active = TRAFFIC["active"]
    if not active:
        return
    if active.get("callsign") == callsign and active.get("kind") == kind:
        TRAFFIC["active"] = None


def _add_recent(entry):
    TRAFFIC["recent"].appendleft(entry)


def _process_traffic_line(line):
    line = line.strip()
    if "YSF, received" not in line:
        return

    log_time = None
    ts = _LOG_TS.match(line)
    if ts:
        log_time = ts.group(1)

    m = _TRAFFIC_PATTERNS["net_data"].search(line)
    if m:
        callsign, dgid, dest = m.group(1), m.group(2), m.group(3)
        callsign = _clean_callsign(callsign)
        entry = _traffic_entry("net", callsign, dgid, dest, log_time=log_time)
        with TRAFFIC_LOCK:
            _set_active(entry)
        return

    m = _TRAFFIC_PATTERNS["net_end"].search(line)
    if m:
        callsign, dgid, dest, duration = m.group(1), m.group(2), m.group(3), m.group(4)
        callsign = _clean_callsign(callsign)
        entry = _traffic_entry("net", callsign, dgid, dest, duration, ended=True, log_time=log_time)
        with TRAFFIC_LOCK:
            _clear_active(callsign, "net")
            _add_recent(entry)
        return

    m = _TRAFFIC_PATTERNS["rf_header"].search(line) or _TRAFFIC_PATTERNS["rf_late"].search(line)
    if m:
        callsign, dgid = m.group(1), m.group(2)
        callsign = _clean_callsign(callsign)
        entry = _traffic_entry("rf", callsign, dgid, log_time=log_time)
        with TRAFFIC_LOCK:
            _set_active(entry)
        return

    m = _TRAFFIC_PATTERNS["rf_end"].search(line)
    if m:
        callsign, dgid, duration = m.group(1), m.group(2), m.group(3)
        callsign = _clean_callsign(callsign)
        entry = _traffic_entry("rf", callsign, dgid, duration=duration, ended=True, log_time=log_time)
        with TRAFFIC_LOCK:
            _clear_active(callsign, "rf")
            _add_recent(entry)


def _journal_lines(args):
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", "mmdvmhost", "--no-pager", "-o", "cat"] + args,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
        return out.decode(errors="replace").splitlines()
    except Exception:
        return []


def _seed_traffic_history():
    for line in _journal_lines(["-n", "400"]):
        _process_traffic_line(line)


def _traffic_snapshot():
    with TRAFFIC_LOCK:
        active = TRAFFIC["active"]
        recent = list(TRAFFIC["recent"])
    incoming = [e for e in recent if e.get("kind") == "net" and not e.get("local")]
    return {
        "active": active,
        "recent": recent[:15],
        "incoming": incoming[:12],
        "on_air": active,
    }


def _tail_mmdvm_journal():
    _seed_traffic_history()
    while True:
        try:
            proc = subprocess.Popen(
                ["journalctl", "-u", "mmdvmhost", "-f", "-n", "0", "--no-pager", "-o", "cat"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
            for line in proc.stdout:
                _process_traffic_line(line)
            proc.wait()
        except Exception:
            pass
        time.sleep(2)

def run(cmd, args=None, sudo=True, timeout=20):
    if args is None:
        args = []
    try:
        base = ["sudo", "-n", cmd] if sudo else [cmd]
        out = subprocess.check_output(base + args, stderr=subprocess.STDOUT, timeout=timeout)
        return True, out.decode(errors="replace").strip()
    except subprocess.CalledProcessError as e:
        msg = (e.output or b"").decode(errors="replace").strip() or str(e)
        return False, msg
    except Exception as e:
        return False, str(e)


def nmcli(*args, timeout=30):
    return run("/usr/bin/nmcli", list(args), timeout=timeout)


def wifi_fallback(*args, timeout=45):
    # sudoers only allows the system-installed path
    return run("/usr/local/bin/wy6y-wifi-fallback", list(args), timeout=timeout)


def _wifi_active_name():
    ok, out = nmcli("-t", "-g", "GENERAL.CONNECTION", "device", "show", "wlan0", timeout=10)
    return out.strip() if ok else ""


def _is_ap_mode():
    ok, out = run("pgrep", ["-f", "hostapd -B /etc/hostapd/hostapd.conf"], sudo=False, timeout=5)
    return ok and bool(out.strip())


def wifi_status_data():
    active = _wifi_active_name()
    if _is_ap_mode():
        return {
            "ok": True,
            "mode": "ap",
            "ssid": "",
            "ip": "192.168.50.1",
            "active": "",
            "ap_ssid": "WY6Y-Hotspot",
            "ap_ip": "192.168.50.1",
        }
    ok, conn = nmcli("-t", "-g", "GENERAL.CONNECTION", "device", "show", "wlan0", timeout=10)
    ssid_val = ""
    if ok and conn.strip():
        conn_name = conn.strip()
        ok2, ssid_val = nmcli("-t", "-g", "802-11-wireless.ssid", "connection", "show", conn_name, timeout=10)
        if not ok2:
            ssid_val = conn_name
    ok, ip_out = run("ip", ["-4", "-o", "addr", "show", "wlan0"], sudo=False, timeout=10)
    ip_val = ""
    if ok:
        parts = ip_out.split()
        if len(parts) > 3:
            ip_val = parts[3].split("/")[0]
    return {
        "ok": True,
        "mode": "client",
        "ssid": ssid_val,
        "ip": ip_val,
        "active": active,
        "ap_ssid": "WY6Y-Hotspot",
        "ap_ip": "192.168.50.1",
    }


def wifi_list_saved():
    ok, out = nmcli("-t", "-f", "NAME,TYPE", "connection", "show", timeout=15)
    if not ok:
        return False, out, []
    active = _wifi_active_name()
    networks = []
    for line in out.splitlines():
        if ":" not in line:
            continue
        name, typ = line.split(":", 1)
        if typ != "802-11-wireless":
            continue
        ok_ssid, ssid = nmcli("-t", "-g", "802-11-wireless.ssid", "connection", "show", name, timeout=10)
        ok_ac, ac = nmcli("-t", "-g", "connection.autoconnect", "connection", "show", name, timeout=10)
        ok_pr, pr = nmcli("-t", "-g", "connection.autoconnect-priority", "connection", "show", name, timeout=10)
        networks.append({
            "name": name,
            "ssid": ssid.strip() if ok_ssid else name,
            "priority": int(pr.strip()) if ok_pr and pr.strip().isdigit() else 0,
            "autoconnect": ac.strip() == "yes" if ok_ac else False,
            "active": name == active,
        })
    networks.sort(key=lambda n: (-n["priority"], n["ssid"]))
    return True, "", networks


def wifi_scan_nearby():
    if _is_ap_mode():
        wifi_fallback("force-client", timeout=20)
        time.sleep(2)
    nmcli("dev", "wifi", "rescan", timeout=15)
    time.sleep(3)
    ok, out = nmcli("-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE", "dev", "wifi", "list", timeout=20)
    if not ok:
        return False, out, []
    results = []
    seen = set()
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) < 4:
            continue
        ssid = parts[0]
        if not ssid or ssid == "--" or ssid in seen:
            continue
        seen.add(ssid)
        results.append({
            "ssid": ssid,
            "signal": int(parts[1]) if parts[1].isdigit() else 0,
            "security": parts[2] or "open",
            "in_use": parts[3] == "*",
        })
    results.sort(key=lambda n: -n["signal"])
    return True, "", results


def wifi_find_connection(target):
    ok, out = nmcli("-t", "-f", "NAME,TYPE", "connection", "show", timeout=15)
    if not ok:
        return ""
    for line in out.splitlines():
        if ":" not in line:
            continue
        name, typ = line.split(":", 1)
        if typ != "802-11-wireless":
            continue
        if name == target:
            return name
        ok_ssid, ssid = nmcli("-t", "-g", "802-11-wireless.ssid", "connection", "show", name, timeout=10)
        if ok_ssid and ssid.strip() == target:
            return name
    return ""


def wifi_add_network(ssid, password, priority="100", connect=True):
    name = ssid.replace(" ", "_")
    existing = wifi_find_connection(ssid)
    if existing:
        ok, msg = nmcli(
            "connection", "modify", existing,
            "wifi.ssid", ssid,
            "wifi-sec.key-mgmt", "wpa-psk",
            "wifi-sec.psk", password,
            "connection.autoconnect", "yes",
            "connection.autoconnect-priority", str(priority),
            timeout=20,
        )
        target = existing
    else:
        ok, msg = nmcli(
            "connection", "add", "type", "wifi", "con-name", name, "ifname", "wlan0", "ssid", ssid,
            "wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", password,
            "connection.autoconnect", "yes", "connection.autoconnect-priority", str(priority),
            "ipv4.method", "auto", "ipv6.method", "auto",
            timeout=20,
        )
        target = name
    if not ok:
        return False, msg
    if not connect:
        return True, f"Saved {ssid}"
    return wifi_connect(target)


def wifi_connect(target):
    name = wifi_find_connection(target)
    if not name:
        return False, f"No saved profile for {target}"
    wifi_fallback("force-client", timeout=15)
    ok, msg = nmcli("connection", "up", name, timeout=60)
    return ok, msg if ok else msg


def wifi_delete_network(target):
    name = wifi_find_connection(target)
    if not name:
        return False, f"No profile for {target}"
    return nmcli("connection", "delete", name, timeout=20)


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            with open(os.path.join(STATIC_DIR, "index.html"), "rb") as f:
                self.wfile.write(f.read())
            return

        if self.path.startswith("/static/"):
            # Very basic static serving
            safe = self.path[1:]  # remove leading /
            full = os.path.join(DASH_DIR, safe)
            if os.path.isfile(full):
                ctype = "text/css" if full.endswith(".css") else "application/javascript" if full.endswith(".js") else "text/plain"
                self.send_response(200)
                self.send_header("Content-type", ctype)
                self.end_headers()
                with open(full, "rb") as f: self.wfile.write(f.read())
                return

        if self.path == "/api/status":
            local_status = os.path.expanduser("~/ysf-status-local")
            status_cmd = local_status if os.path.isfile(local_status) else os.environ.get("YSF_STATUS", "/usr/local/bin/ysf-status")
            ok, out = run(status_cmd, sudo=False)
            if ok:
                try:
                    data = json.loads(out)
                except:
                    data = {"error": "parse"}
            else:
                data = {"error": out, "gateway_active": False}
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
            return

        if self.path == "/api/traffic":
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(_traffic_snapshot()).encode())
            return

        if self.path == "/api/wifi/status":
            self._json(wifi_status_data())
            return

        if self.path == "/api/wifi/networks":
            ok, err, networks = wifi_list_saved()
            self._json({"ok": ok, "networks": networks, "error": err})
            return

        if self.path == "/api/wifi/scan":
            ok, err, networks = wifi_scan_nearby()
            self._json({"ok": ok, "networks": networks, "error": err})
            return

        if self.path == "/api/log":
            lines = []
            ysf_log = os.path.expanduser("~/tmp/ysf.log") if os.path.isfile("/tmp/ysf.log") else "/tmp/ysf.log"
            if os.path.isfile(ysf_log):
                try:
                    with open(ysf_log, "r", errors="replace") as f:
                        lines = [l for l in f.read().splitlines() if l.strip()][-20:]
                except Exception:
                    pass
            if not lines:
                try:
                    out = subprocess.check_output(["journalctl", "-u", "ysfgateway", "-n", "25", "--no-pager", "-o", "cat"],
                                                  stderr=subprocess.STDOUT, timeout=5)
                    lines = [l for l in out.decode(errors="replace").splitlines() if l.strip()][-20:]
                except Exception as e:
                    lines = [str(e)]
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"lines": lines}).encode())
            return

        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        global LAST
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode() if length else ""
        data = {}
        try:
            data = json.loads(body) if body else {}
        except: pass

        if self.path == "/api/link":
            target = data.get("target", "").strip()
            if not target:
                self._json({"ok": False, "error": "no target"})
                return
            ok, msg = run("/usr/local/bin/ysf-link", [target])
            if ok: LAST = target
            self._json({"ok": ok, "message": msg, "target": target})

        elif self.path == "/api/unlink":
            ok, msg = run("/usr/local/bin/ysf-unlink")
            self._json({"ok": ok, "message": msg})

        elif self.path == "/api/reconnect_last":
            if not LAST:
                ok, out = run("/usr/local/bin/ysf-status")
                if ok:
                    try: LAST = json.loads(out).get("last_linked", "")
                    except: pass
            if not LAST:
                self._json({"ok": False, "error": "no last link"})
                return
            ok, msg = run("/usr/local/bin/ysf-link", [LAST])
            self._json({"ok": ok, "message": msg, "target": LAST})

        elif self.path == "/api/wifi/add":
            ssid = (data.get("ssid") or "").strip()
            password = data.get("password") or ""
            priority = str(data.get("priority") or "100")
            connect = bool(data.get("connect", True))
            if not ssid or not password:
                self._json({"ok": False, "error": "ssid and password required"})
                return
            ok, msg = wifi_add_network(ssid, password, priority, connect)
            self._json({"ok": ok, "message": msg, "ssid": ssid})

        elif self.path == "/api/wifi/connect":
            target = (data.get("name") or data.get("ssid") or "").strip()
            if not target:
                self._json({"ok": False, "error": "name or ssid required"})
                return
            ok, msg = wifi_connect(target)
            self._json({"ok": ok, "message": msg, "target": target})

        elif self.path == "/api/wifi/delete":
            target = (data.get("name") or data.get("ssid") or "").strip()
            if not target:
                self._json({"ok": False, "error": "name or ssid required"})
                return
            ok, msg = wifi_delete_network(target)
            self._json({"ok": ok, "message": msg, "target": target})

        elif self.path == "/api/wifi":
            mode = data.get("mode", "check")
            if mode in ("force-ap", "force-client"):
                ok, msg = wifi_fallback(mode, timeout=30)
            else:
                ok, msg = True, json.dumps(wifi_status_data())
            self._json({"ok": ok, "message": msg})
        else:
            self._json({"ok": False, "error": "unknown"})

    def _json(self, obj):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

if __name__ == "__main__":
    os.chdir(DASH_DIR)
    threading.Thread(target=_tail_mmdvm_journal, daemon=True).start()
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        print(f"CyberFusion dashboard on port {PORT}")
        httpd.serve_forever()
