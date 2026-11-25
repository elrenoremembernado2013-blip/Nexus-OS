#!/usr/bin/env python3
"""Real Linux Mint user-session backend bridge for NEXUS OS Phase 4 core apps.

Provides:
  1. Real GNU Bash PTY sessions (pty.openpty + /bin/bash -i)
  2. Real /proc + statvfs + sysfs hardware/process telemetry (never synthetic)
  3. Allowlisted Linux Mint desktop tool launcher (Files, Settings, Browser, Store)
  4. Loopback-only authenticated HTTP API (--serve) locked to a per-run token

Runs strictly as the logged-in non-root desktop user.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import pwd
import secrets
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import threading
import time
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO_ROOT = Path(__file__).resolve().parents[2]

ALLOWLISTED_TOOLS: dict[str, list[list[str]]] = {
    "files": [["nemo"], ["thunar"], ["xdg-open", str(Path.home())]],
    "browser": [["firefox"], ["chromium"], ["chromium-browser"], ["x-www-browser"]],
    "terminal": [["xfce4-terminal"], ["gnome-terminal"], ["x-terminal-emulator"]],
    "monitor": [["gnome-system-monitor"], ["xfce4-taskmanager"], ["mate-system-monitor"]],
    "display": [["cinnamon-settings", "display"], ["xfce4-display-settings"]],
    "sound": [["cinnamon-settings", "sound"], ["pavucontrol"]],
    "network": [["cinnamon-settings", "network"], ["nm-connection-editor"]],
    "bluetooth": [["cinnamon-settings", "bluetooth"], ["blueman-manager"]],
    "power": [["cinnamon-settings", "power"], ["xfce4-power-manager-settings"]],
    "accounts": [["cinnamon-settings", "users"], ["users-admin"]],
    "privacy-security": [["cinnamon-settings", "privacy"], ["gufw"]],
    "packages": [["mintinstall"], ["mintupdate"]],
    "gaming": [["steam"]],
    "installer": [["nexus-installer-launcher"], ["ubiquity"]],
}


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def read_cpu_percent(sample_seconds: float = 0.08) -> float | None:
    def parse_stat() -> tuple[int, int] | None:
        raw = read_text(Path("/proc/stat"))
        if not raw:
            return None
        for line in raw.splitlines():
            if line.startswith("cpu "):
                parts = [int(x) for x in line.split()[1:8]]
                idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
                total = sum(parts)
                return idle, total
        return None

    first = parse_stat()
    if not first:
        return None
    time.sleep(sample_seconds)
    second = parse_stat()
    if not second:
        return None
    idle_delta = second[0] - first[0]
    total_delta = second[1] - first[1]
    if total_delta <= 0:
        return None
    usage = 100.0 * (1.0 - (idle_delta / total_delta))
    return round(max(0.0, min(100.0, usage)), 1)


def read_memory() -> dict[str, object] | None:
    raw = read_text(Path("/proc/meminfo"))
    if not raw:
        return None
    values: dict[str, int] = {}
    for line in raw.splitlines():
        if ":" not in line:
            continue
        key, rest = line.split(":", 1)
        num = rest.strip().split()[0]
        if num.isdigit():
            values[key] = int(num)
    total_kb = values.get("MemTotal")
    avail_kb = values.get("MemAvailable", values.get("MemFree"))
    if not total_kb or avail_kb is None:
        return None
    used_kb = max(0, total_kb - avail_kb)
    return {
        "total_mib": round(total_kb / 1024),
        "used_mib": round(used_kb / 1024),
        "available_mib": round(avail_kb / 1024),
        "percent": round((used_kb / total_kb) * 100.0, 1),
    }


def read_storage() -> dict[str, object] | None:
    try:
        st = os.statvfs("/")
    except OSError:
        return None
    total = st.f_blocks * st.f_frsize
    avail = st.f_bavail * st.f_frsize
    used = max(0, total - (st.f_bfree * st.f_frsize))
    gib = 1024 ** 3
    return {
        "mount": "/",
        "total_gib": round(total / gib, 1),
        "used_gib": round(used / gib, 1),
        "available_gib": round(avail / gib, 1),
    }


def read_network() -> dict[str, object] | None:
    raw = read_text(Path("/proc/net/dev"))
    if not raw:
        return None
    rx_total = 0
    tx_total = 0
    interfaces: list[str] = []
    for line in raw.splitlines()[2:]:
        if ":" not in line:
            continue
        iface, data = line.split(":", 1)
        iface = iface.strip()
        if iface == "lo":
            continue
        cols = data.split()
        if len(cols) >= 9:
            interfaces.append(iface)
            rx_total += int(cols[0])
            tx_total += int(cols[8])
    return {
        "interfaces": interfaces,
        "rx_mib": round(rx_total / (1024 ** 2), 2),
        "tx_mib": round(tx_total / (1024 ** 2), 2),
    }


def read_battery() -> dict[str, object] | None:
    for bat in sorted(Path("/sys/class/power_supply").glob("BAT*")):
        cap = read_text(bat / "capacity")
        status = read_text(bat / "status")
        if cap is not None and cap.isdigit():
            return {"device": bat.name, "percent": int(cap), "status": status or "unknown"}
    return None


def read_temperature() -> dict[str, object] | None:
    for zone in sorted(Path("/sys/class/thermal").glob("thermal_zone*")):
        raw = read_text(zone / "temp")
        ztype = read_text(zone / "type") or zone.name
        if raw and raw.lstrip("-").isdigit():
            celsius = round(int(raw) / 1000.0, 1)
            if -30.0 <= celsius <= 150.0:
                return {"sensor": ztype, "celsius": celsius}
    return None


def read_processes(limit: int = 8) -> list[dict[str, object]]:
    procs: list[dict[str, object]] = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        status_raw = read_text(entry / "status")
        if not status_raw:
            continue
        name = entry.name
        uid = None
        rss_kb = 0
        for line in status_raw.splitlines():
            if line.startswith("Name:"):
                name = line.split(":", 1)[1].strip()
            elif line.startswith("Uid:"):
                parts = line.split(":", 1)[1].split()
                if parts and parts[0].isdigit():
                    uid = int(parts[0])
            elif line.startswith("VmRSS:"):
                parts = line.split(":", 1)[1].split()
                if parts and parts[0].isdigit():
                    rss_kb = int(parts[0])
        user = str(uid) if uid is not None else "unknown"
        if uid is not None:
            try:
                user = pwd.getpwuid(uid).pw_name
            except KeyError:
                pass
        procs.append({"pid": pid, "name": name, "user": user, "rss_mib": round(rss_kb / 1024, 1)})
    procs.sort(key=lambda p: float(p["rss_mib"]), reverse=True)
    return procs[:limit]


def collect_telemetry_snapshot() -> dict[str, object]:
    cpu_pct = read_cpu_percent()
    load_raw = read_text(Path("/proc/loadavg"))
    load_1m = load_raw.split()[0] if load_raw else None
    mem = read_memory()
    storage = read_storage()
    net = read_network()
    bat = read_battery()
    temp = read_temperature()
    procs = read_processes()

    return {
        "processor": {
            "summary": f"{cpu_pct}% used" if cpu_pct is not None else "Unavailable",
            "detail": f"Load avg (1m): {load_1m}" if load_1m else "CPU telemetry unavailable",
        },
        "memory": {
            "summary": f"{mem['used_mib']} / {mem['total_mib']} MiB ({mem['percent']}%)" if mem else "Unavailable",
            "detail": f"{mem['available_mib']} MiB available" if mem else "Memory telemetry unavailable",
        },
        "storage": {
            "summary": f"{storage['used_gib']} / {storage['total_gib']} GiB" if storage else "Unavailable",
            "detail": f"{storage['available_gib']} GiB free on /" if storage else "Storage telemetry unavailable",
        },
        "processes": {
            "summary": f"Top {len(procs)} by RSS" if procs else "Unavailable",
            "detail": ", ".join(f"{p['name']} ({p['rss_mib']} MiB)" for p in procs[:3]) if procs else "Process list unavailable",
            "items": procs,
        },
        "network": {
            "summary": f"{len(net['interfaces'])} iface(s)" if net else "Unavailable",
            "detail": f"RX {net['rx_mib']} MiB · TX {net['tx_mib']} MiB" if net else "Network telemetry unavailable",
        },
        "battery": {
            "summary": f"{bat['percent']}% ({bat['status']})" if bat else "Unavailable",
            "detail": bat["device"] if bat else "No battery reported on this host",
        },
        "temperature": {
            "summary": f"{temp['celsius']} °C" if temp else "Unavailable",
            "detail": temp["sensor"] if temp else "No readable thermal sensor",
        },
    }


def list_available_tools() -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for category, candidates in ALLOWLISTED_TOOLS.items():
        chosen = None
        for cmd in candidates:
            if shutil.which(cmd[0]):
                chosen = cmd
                break
        result[category] = {
            "available": chosen is not None,
            "command": chosen[0] if chosen else None,
        }
    return result


def launch_allowlisted_tool(category: str) -> dict[str, object]:
    candidates = ALLOWLISTED_TOOLS.get(category)
    if not candidates:
        return {"ok": False, "message": f"Unknown tool category: {category}"}
    for cmd in candidates:
        if shutil.which(cmd[0]):
            subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return {"ok": True, "command": cmd[0], "message": f"Launched {cmd[0]}"}
    return {"ok": False, "message": f"No supported Linux tool installed for {category}."}


class TerminalSessionManager:
    """Manages interactive GNU Bash PTY sessions for the logged-in user."""

    def __init__(self, max_sessions: int = 8) -> None:
        self._sessions: dict[str, dict[str, object]] = {}
        self._lock = threading.Lock()
        self._max_sessions = max_sessions

    def open_session(self, cols: int = 80, rows: int = 24) -> str:
        bash_path = shutil.which("bash") or "/bin/bash"
        if not os.path.exists(bash_path):
            raise RuntimeError("GNU Bash (/bin/bash) was not found on this host.")
        with self._lock:
            if len(self._sessions) >= self._max_sessions:
                raise RuntimeError("Maximum concurrent terminal sessions reached.")
            master_fd, slave_fd = pty.openpty()
            self._set_winsize(master_fd, cols, rows)
            env = {
                "TERM": "xterm-256color",
                "HOME": str(Path.home()),
                "USER": os.environ.get("USER", pwd.getpwuid(os.getuid()).pw_name),
                "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
                "SHELL": bash_path,
                "LANG": os.environ.get("LANG", "C.UTF-8"),
            }
            proc = subprocess.Popen(
                [bash_path, "-i"],
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                cwd=str(Path.home()),
                env=env,
                start_new_session=True,
                close_fds=True,
            )
            os.close(slave_fd)
            os.set_blocking(master_fd, False)
            sid = secrets.token_hex(12)
            self._sessions[sid] = {"fd": master_fd, "proc": proc}
            return sid

    @staticmethod
    def _set_winsize(fd: int, cols: int, rows: int) -> None:
        cols = max(20, min(300, int(cols)))
        rows = max(5, min(120, int(rows)))
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def read(self, sid: str, timeout: float = 0.05) -> tuple[str, int | None]:
        with self._lock:
            sess = self._sessions.get(sid)
        if not sess:
            raise KeyError(f"Unknown session: {sid}")
        fd = int(sess["fd"])
        proc = sess["proc"]
        assert isinstance(proc, subprocess.Popen)
        chunks: list[bytes] = []
        ready, _, _ = select.select([fd], [], [], timeout)
        if ready:
            while True:
                try:
                    data = os.read(fd, 4096)
                    if not data:
                        break
                    chunks.append(data)
                except BlockingIOError:
                    break
                except OSError:
                    break
        exit_code = proc.poll()
        return b"".join(chunks).decode("utf-8", errors="replace"), exit_code

    def write(self, sid: str, data: str) -> None:
        with self._lock:
            sess = self._sessions.get(sid)
        if not sess:
            raise KeyError(f"Unknown session: {sid}")
        os.write(int(sess["fd"]), data.encode("utf-8", errors="replace"))

    def resize(self, sid: str, cols: int, rows: int) -> None:
        with self._lock:
            sess = self._sessions.get(sid)
        if not sess:
            raise KeyError(f"Unknown session: {sid}")
        self._set_winsize(int(sess["fd"]), cols, rows)

    def interrupt(self, sid: str) -> None:
        with self._lock:
            sess = self._sessions.get(sid)
        if not sess:
            raise KeyError(f"Unknown session: {sid}")
        proc = sess["proc"]
        assert isinstance(proc, subprocess.Popen)
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGINT)

    def close_session(self, sid: str) -> None:
        with self._lock:
            sess = self._sessions.pop(sid, None)
        if not sess:
            return
        fd = int(sess["fd"])
        proc = sess["proc"]
        assert isinstance(proc, subprocess.Popen)
        try:
            os.close(fd)
        except OSError:
            pass
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=1.5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait(timeout=1.0)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    pass

    def close_all(self) -> None:
        with self._lock:
            sids = list(self._sessions.keys())
        for sid in sids:
            self.close_session(sid)


def run_bash_pty_self_test() -> dict[str, object]:
    mgr = TerminalSessionManager()
    sid = mgr.open_session(cols=100, rows=30)
    try:
        mgr.resize(sid, 120, 40)
        mgr.write(sid, 'printf "BASH_OK:%s\\n" "$BASH_VERSION"\n')
        deadline = time.monotonic() + 3.0
        output = ""
        matched_line = None
        while time.monotonic() < deadline:
            chunk, _ = mgr.read(sid, timeout=0.05)
            output += chunk
            for line in output.splitlines():
                clean = line.strip()
                if clean.startswith("BASH_OK:") and len(clean) > len("BASH_OK:"):
                    matched_line = clean
                    break
            if matched_line:
                break
        if not matched_line:
            raise RuntimeError(f"Did not observe Bash PTY execution output; got: {output!r}")
        mgr.interrupt(sid)
        return {"ok": True, "bash_output_sample": matched_line}
    finally:
        mgr.close_session(sid)


def serve_loopback(port: int) -> None:
    if os.geteuid() == 0:
        raise SystemExit("Refusing to run NEXUS desktop bridge as root.")
    token = secrets.token_urlsafe(32)
    pty_mgr = TerminalSessionManager()

    class BridgeHandler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: object) -> None:
            return

        def _authorized(self) -> bool:
            if self.headers.get("X-Nexus-Token") != token:
                return False
            origin = self.headers.get("Origin")
            if origin and origin not in (f"http://127.0.0.1:{port}", f"http://localhost:{port}"):
                return False
            return True

        def _send_json(self, code: int, payload: object) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _read_json(self) -> dict[str, object]:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 65536:
                return {}
            return json.loads(self.rfile.read(length).decode("utf-8"))

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            if not self._authorized():
                self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid X-Nexus-Token"})
                return
            if parsed.path == "/api/telemetry":
                self._send_json(HTTPStatus.OK, collect_telemetry_snapshot())
            elif parsed.path == "/api/security/status":
                sec_cli = Path(__file__).resolve().with_name("nexus-security-cli.sh")
                proc = subprocess.run(
                    ["bash", str(sec_cli), "status"],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                self._send_json(HTTPStatus.OK, json.loads(proc.stdout))
            elif parsed.path == "/api/gaming/status":
                gam_cli = Path(__file__).resolve().with_name("nexus-gaming-cli.sh")
                proc = subprocess.run(
                    ["bash", str(gam_cli), "status"],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                self._send_json(HTTPStatus.OK, json.loads(proc.stdout))
            elif parsed.path == "/api/installer/preflight":
                pre_cli = Path(__file__).resolve().parents[1] / "installer" / "nexus-install-preflight.sh"
                proc = subprocess.run(
                    ["bash", str(pre_cli)],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                self._send_json(HTTPStatus.OK, json.loads(proc.stdout))
            elif parsed.path == "/api/tools":
                self._send_json(HTTPStatus.OK, list_available_tools())
            elif parsed.path == "/api/terminal/read":
                qs = urllib.parse.parse_qs(parsed.query)
                sid = (qs.get("sessionId") or [""])[0]
                try:
                    data, exit_code = pty_mgr.read(sid)
                    self._send_json(HTTPStatus.OK, {"output": data, "exitCode": exit_code})
                except KeyError as err:
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": str(err)})
            else:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "Unknown API endpoint"})

        def do_POST(self) -> None:
            if not self._authorized():
                self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid X-Nexus-Token"})
                return
            body = self._read_json()
            if self.path == "/api/terminal/open":
                sid = pty_mgr.open_session(int(body.get("cols", 80)), int(body.get("rows", 24)))
                self._send_json(HTTPStatus.OK, {"sessionId": sid})
            elif self.path == "/api/terminal/write":
                pty_mgr.write(str(body.get("sessionId", "")), str(body.get("data", "")))
                self._send_json(HTTPStatus.OK, {"ok": True})
            elif self.path == "/api/terminal/resize":
                pty_mgr.resize(str(body.get("sessionId", "")), int(body.get("cols", 80)), int(body.get("rows", 24)))
                self._send_json(HTTPStatus.OK, {"ok": True})
            elif self.path == "/api/terminal/interrupt":
                pty_mgr.interrupt(str(body.get("sessionId", "")))
                self._send_json(HTTPStatus.OK, {"ok": True})
            elif self.path == "/api/terminal/close":
                pty_mgr.close_session(str(body.get("sessionId", "")))
                self._send_json(HTTPStatus.OK, {"ok": True})
            elif self.path == "/api/tools/launch":
                res = launch_allowlisted_tool(str(body.get("category", "")))
                self._send_json(HTTPStatus.OK if res["ok"] else HTTPStatus.BAD_REQUEST, res)
            elif self.path == "/api/gaming/mode":
                mode_action = str(body.get("action", ""))
                if mode_action not in ("enable", "disable"):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid gaming mode action"})
                    return
                gam_cli = Path(__file__).resolve().with_name("nexus-gaming-cli.sh")
                proc = subprocess.run(
                    ["bash", str(gam_cli), "gaming-mode", mode_action],
                    capture_output=True,
                    text=True,
                )
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.INTERNAL_SERVER_ERROR,
                    {"ok": proc.returncode == 0, "message": proc.stdout.strip() or proc.stderr.strip()},
                )
            elif self.path == "/api/personalisation/apply":
                cinnamon_cli = Path(__file__).resolve().parents[1] / "cinnamon" / "apply-nexus-cinnamon.sh"
                cmd = ["bash", str(cinnamon_cli)]
                if body.get("dryRun"):
                    cmd.append("--dry-run")
                if body.get("revert"):
                    cmd.append("--revert")
                else:
                    if body.get("theme") in ("midnight", "nebula", "arctic", "emerald", "solar"):
                        cmd.extend(["--theme", str(body["theme"])])
                    if body.get("effectLevel") in ("off", "subtle", "balanced", "enhanced"):
                        cmd.extend(["--effect-level", str(body["effectLevel"])])
                    if body.get("dockPosition") in ("bottom", "left", "right"):
                        cmd.extend(["--dock-position", str(body["dockPosition"])])
                    if body.get("panelSize") in ("small", "medium", "large"):
                        cmd.extend(["--panel-size", str(body["panelSize"])])
                    if body.get("panelAutohide") in ("false", "true", "intel"):
                        cmd.extend(["--panel-autohide", str(body["panelAutohide"])])
                    if body.get("wallpaperFit") in ("zoom", "scaled", "stretched", "centered", "wallpaper"):
                        cmd.extend(["--wallpaper-fit", str(body["wallpaperFit"])])
                    if isinstance(body.get("workspaces"), int) and 1 <= body["workspaces"] <= 8:
                        cmd.extend(["--workspaces", str(body["workspaces"])])
                    if body.get("presetProfile") in ("default", "minimal", "gaming", "productivity", "cinematic", "lightweight"):
                        cmd.extend(["--preset-profile", str(body["presetProfile"])])
                proc = subprocess.run(cmd, capture_output=True, text=True)
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "output": (proc.stdout + proc.stderr).strip()},
                )
            else:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "Unknown API endpoint"})

    server = ThreadingHTTPServer(("127.0.0.1", port), BridgeHandler)
    actual_port = server.server_address[1]
    print(json.dumps({"url": f"http://127.0.0.1:{actual_port}", "token": token}), flush=True)
    try:
        server.serve_forever()
    finally:
        pty_mgr.close_all()
        server.server_close()


def main() -> int:
    parser = argparse.ArgumentParser(description="NEXUS OS Linux Mint local system bridge")
    parser.add_argument("--telemetry", action="store_true", help="Print real /proc + sysfs telemetry JSON")
    parser.add_argument("--tools", action="store_true", help="Print detected Linux Mint desktop tools JSON")
    parser.add_argument("--bash-check", action="store_true", help="Verify real GNU Bash PTY open/write/read/close")
    parser.add_argument("--serve", action="store_true", help="Run loopback-only authenticated local bridge API")
    parser.add_argument("--port", type=int, default=0, help="Loopback port for --serve (default: ephemeral)")
    args = parser.parse_args()

    if args.telemetry:
        print(json.dumps(collect_telemetry_snapshot(), indent=2))
        return 0
    if args.tools:
        print(json.dumps(list_available_tools(), indent=2))
        return 0
    if args.bash_check:
        print(json.dumps(run_bash_pty_self_test(), indent=2))
        return 0
    if args.serve:
        serve_loopback(args.port)
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
