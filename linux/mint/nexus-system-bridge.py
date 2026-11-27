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
import re
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
    "files": [["nemo"], ["pcmanfm-qt"], ["pcmanfm"], ["thunar"], ["xdg-open", str(Path.home())]],
    "browser": [["firefox"], ["chromium"], ["chromium-browser"], ["falkon"], ["x-www-browser"]],
    "terminal": [["qterminal"], ["lxterminal"], ["gnome-terminal"], ["xfce4-terminal"], ["x-terminal-emulator"]],
    "monitor": [["gnome-system-monitor"], ["qps"], ["lxtask"], ["xfce4-taskmanager"], ["mate-system-monitor"]],
    "display": [["cinnamon-settings", "display"], ["xfce4-display-settings"], ["lxqt-config-monitor"], ["lxrandr"], ["arandr"]],
    "sound": [["cinnamon-settings", "sound"], ["pavucontrol-qt"], ["pavucontrol"]],
    "network": [["cinnamon-settings", "network"], ["nm-connection-editor"]],
    "bluetooth": [["cinnamon-settings", "bluetooth"], ["blueman-manager"]],
    "power": [["cinnamon-settings", "power"], ["xfce4-power-manager-settings"], ["lxqt-config-power"]],
    "accounts": [["cinnamon-settings", "users"], ["users-admin"], ["lxqt-admin-user"]],
    "privacy-security": [["cinnamon-settings", "privacy"], ["gufw"]],
    "packages": [["mintinstall"], ["mintupdate"]],
    "gaming": [["steam"]],
    "installer": [["nexus-installer-launcher"], ["ubiquity"]],
}

TOOL_INSTALL_HINTS: dict[str, str] = {
    "files": "install nemo, thunar, pcmanfm, or pcmanfm-qt",
    "browser": "install firefox or falkon via NEXUS Store",
    "terminal": "install qterminal, lxterminal, gnome-terminal, or xfce4-terminal",
    "monitor": "install gnome-system-monitor, xfce4-taskmanager, lxtask, or qps",
    "display": "install arandr, lxrandr, or lxqt-config",
    "sound": "install pavucontrol or pavucontrol-qt",
    "network": "install network-manager-gnome (nm-connection-editor)",
    "bluetooth": "install blueman (blueman-manager)",
    "power": "install xfce4-power-manager or lxqt-powermanagement",
    "accounts": "install gnome-system-tools (users-admin) or lxqt-admin",
    "privacy-security": "install gufw for graphical firewall management",
    "packages": "use nexus-store-cli in a terminal or install mintinstall",
    "gaming": "install steam-installer via NEXUS Store",
    "installer": "install ubiquity or run nexus-installer-launcher",
}


def resolve_helper(repo_rel: str, installed_name: str) -> list[str]:
    candidate = REPO_ROOT / repo_rel
    if candidate.is_file():
        return ["bash", str(candidate)]
    installed = shutil.which(installed_name)
    if installed:
        return [installed]
    raise FileNotFoundError(f"Missing helper {repo_rel} and {installed_name}")


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def read_cpu_percent(sample_seconds: float = 0.08, proc_root: Path = Path("/proc")) -> float | None:
    def parse_stat() -> tuple[int, int] | None:
        raw = read_text(proc_root / "stat")
        if not raw:
            return None
        for line in raw.splitlines():
            if line.startswith("cpu "):
                cols = line.split()[1:8]
                if len(cols) < 4 or not all(col.isdigit() for col in cols):
                    return None
                parts = [int(x) for x in cols]
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


def read_memory(proc_root: Path = Path("/proc")) -> dict[str, object] | None:
    raw = read_text(proc_root / "meminfo")
    if not raw:
        return None
    values: dict[str, int] = {}
    for line in raw.splitlines():
        if ":" not in line:
            continue
        key, rest = line.split(":", 1)
        toks = rest.strip().split()
        if toks and toks[0].isdigit():
            values[key] = int(toks[0])
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


def read_storage(mount: str = "/") -> dict[str, object] | None:
    try:
        st = os.statvfs(mount)
    except OSError:
        return None
    total = st.f_blocks * st.f_frsize
    avail = st.f_bavail * st.f_frsize
    used = max(0, total - (st.f_bfree * st.f_frsize))
    gib = 1024 ** 3
    return {
        "mount": mount,
        "total_gib": round(total / gib, 1),
        "used_gib": round(used / gib, 1),
        "available_gib": round(avail / gib, 1),
    }


def read_network(proc_root: Path = Path("/proc")) -> dict[str, object] | None:
    raw = read_text(proc_root / "net" / "dev")
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
        if len(cols) >= 9 and cols[0].isdigit() and cols[8].isdigit():
            interfaces.append(iface)
            rx_total += int(cols[0])
            tx_total += int(cols[8])
    return {
        "interfaces": interfaces,
        "rx_mib": round(rx_total / (1024 ** 2), 2),
        "tx_mib": round(tx_total / (1024 ** 2), 2),
    }


def read_battery(sys_root: Path = Path("/sys")) -> dict[str, object] | None:
    ps_dir = sys_root / "class" / "power_supply"
    try:
        entries = sorted(ps_dir.glob("BAT*"))
    except OSError:
        return None
    for bat in entries:
        cap = read_text(bat / "capacity")
        status = read_text(bat / "status")
        if cap is not None and cap.isdigit():
            return {"device": bat.name, "percent": int(cap), "status": status or "unknown"}
    return None


def read_temperature(sys_root: Path = Path("/sys")) -> dict[str, object] | None:
    thermal_dir = sys_root / "class" / "thermal"
    try:
        zones = sorted(thermal_dir.glob("thermal_zone*"))
    except OSError:
        return None
    for zone in zones:
        raw = read_text(zone / "temp")
        ztype = read_text(zone / "type") or zone.name
        if raw and raw.lstrip("-").isdigit():
            celsius = round(int(raw) / 1000.0, 1)
            if -30.0 <= celsius <= 150.0:
                return {"sensor": ztype, "celsius": celsius}
    return None


def read_processes(limit: int = 8, proc_root: Path = Path("/proc")) -> list[dict[str, object]]:
    procs: list[dict[str, object]] = []
    try:
        entries = list(proc_root.iterdir())
    except OSError:
        return procs
    for entry in entries:
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


def collect_telemetry_snapshot(
    proc_root: Path = Path("/proc"),
    sys_root: Path = Path("/sys"),
    storage_mount: str = "/",
    sample_seconds: float = 0.08,
) -> dict[str, object]:
    cpu_pct = read_cpu_percent(sample_seconds=sample_seconds, proc_root=proc_root)
    load_raw = read_text(proc_root / "loadavg")
    load_tokens = load_raw.split() if load_raw else []
    load_1m = load_tokens[0] if load_tokens else None
    mem = read_memory(proc_root=proc_root)
    storage = read_storage(mount=storage_mount)
    net = read_network(proc_root=proc_root)
    bat = read_battery(sys_root=sys_root)
    temp = read_temperature(sys_root=sys_root)
    procs = read_processes(proc_root=proc_root)

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
            "detail": f"{storage['available_gib']} GiB free on {storage_mount}" if storage else "Storage telemetry unavailable",
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


def detect_desktop_edition() -> str:
    xdg = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    if "cinnamon" in xdg:
        return "cinnamon"
    if "xfce" in xdg:
        return "xfce"
    if "lxqt" in xdg:
        return "lite-lxqt"
    if "openbox" in xdg:
        return "lite"
    rel = read_text(Path("/etc/nexus-os-release")) or ""
    if 'NEXUS_EDITION="lite-lxqt"' in rel or 'NEXUS_DESKTOP="lxqt"' in rel:
        return "lite-lxqt"
    if 'NEXUS_EDITION="lite"' in rel or 'NEXUS_DESKTOP="openbox"' in rel:
        return "lite"
    if 'NEXUS_DESKTOP="cinnamon"' in rel:
        return "cinnamon"
    if 'NEXUS_DESKTOP="xfce"' in rel:
        return "xfce"
    if shutil.which("cinnamon-session"):
        return "cinnamon"
    if shutil.which("lxqt-session"):
        return "lite-lxqt"
    if shutil.which("xfce4-session"):
        return "xfce"
    if shutil.which("openbox"):
        return "lite"
    return "cinnamon"


def resolve_personalisation_cmd(body: dict[str, object]) -> list[str]:
    edition = str(body.get("edition") or "").strip().lower() or detect_desktop_edition()
    if edition == "xfce":
        cmd = resolve_helper("linux/mint/apply-nexus-xfce.sh", "nexus-apply-xfce")
        if body.get("dryRun"):
            cmd.append("--dry-run")
        if body.get("revert"):
            cmd.append("--revert")
        elif body.get("effectLevel") == "off" or body.get("presetProfile") in ("minimal", "lightweight", "gaming"):
            cmd.append("--lightweight")
        return cmd
    if edition == "lite-lxqt":
        cmd = resolve_helper("linux/lite/scripts/apply-nexus-lite-lxqt.sh", "nexus-apply-lite-lxqt")
        if body.get("dryRun"):
            cmd.append("--dry-run")
        if body.get("revert"):
            cmd.append("--revert")
        else:
            profile = str(body.get("liteProfile") or "lite-1g")
            if profile in ("lite-512", "lite-768", "lite-1g", "lite-2g", "lite-4g"):
                cmd.extend(["--profile", profile])
        return cmd
    if edition == "lite":
        cmd = resolve_helper("linux/lite/apply-nexus-lite.sh", "nexus-apply-lite")
        if body.get("dryRun"):
            cmd.append("--dry-run")
        if body.get("revert"):
            cmd.append("--revert")
        else:
            profile = str(body.get("liteProfile") or "lite-1g")
            if profile in ("lite-512", "lite-1g", "standard-2g"):
                cmd.extend(["--profile", profile])
        return cmd

    cmd = resolve_helper("linux/cinnamon/apply-nexus-cinnamon.sh", "nexus-apply-cinnamon")
    if body.get("dryRun"):
        cmd.append("--dry-run")
    if body.get("revert"):
        cmd.append("--revert")
    else:
        if body.get("theme") in ("midnight", "nebula", "arctic", "emerald", "solar"):
            cmd.extend(["--theme", str(body["theme"])])
        if isinstance(body.get("accent"), str) and re.fullmatch(r"#[0-9a-fA-F]{6}", body["accent"]):
            cmd.extend(["--accent", body["accent"]])
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
    return cmd


def launch_allowlisted_tool(category: str) -> dict[str, object]:
    candidates = ALLOWLISTED_TOOLS.get(category)
    if not candidates:
        return {"ok": False, "message": f"Unknown tool category: {category}"}
    for cmd in candidates:
        if shutil.which(cmd[0]):
            if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
                return {
                    "ok": False,
                    "command": cmd[0],
                    "message": f"Cannot launch {cmd[0]}: no active X11 or Wayland display session.",
                }
            try:
                subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return {"ok": True, "command": cmd[0], "message": f"Launched {cmd[0]}"}
            except OSError as err:
                return {"ok": False, "command": cmd[0], "message": f"Failed to launch {cmd[0]}: {err}"}
    hint = TOOL_INSTALL_HINTS.get(category, "")
    suffix = f" ({hint})" if hint else ""
    return {"ok": False, "message": f"No supported Linux tool installed for {category}{suffix}."}


class TerminalSessionManager:
    """Manages interactive GNU Bash PTY sessions for the logged-in user."""

    def __init__(self, max_sessions: int = 8) -> None:
        self._sessions: dict[str, dict[str, object]] = {}
        self._lock = threading.Lock()
        self._max_sessions = max_sessions

    def _cleanup_exited_locked(self) -> None:
        now = time.monotonic()
        expired = []
        for sid, sess in self._sessions.items():
            proc = sess["proc"]
            assert isinstance(proc, subprocess.Popen)
            if proc.poll() is not None:
                exited_at = sess.get("exited_at")
                if exited_at is None:
                    sess["exited_at"] = now
                elif now - float(exited_at) > 30.0:
                    expired.append(sid)
        for sid in expired:
            sess = self._sessions.pop(sid, None)
            if sess:
                try:
                    os.close(int(sess["fd"]))
                except OSError:
                    pass

    def active_session_ids(self) -> list[str]:
        with self._lock:
            self._cleanup_exited_locked()
            return list(self._sessions.keys())

    def open_session(self, cols: int = 80, rows: int = 24) -> str:
        bash_path = shutil.which("bash") or "/bin/bash"
        if not os.path.exists(bash_path):
            raise RuntimeError("GNU Bash (/bin/bash) was not found on this host.")
        with self._lock:
            self._cleanup_exited_locked()
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
            self._sessions[sid] = {"fd": master_fd, "proc": proc, "exited_at": None}
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
            raise KeyError(f"Unknown or closed session: {sid}")
        fd = int(sess["fd"])
        proc = sess["proc"]
        assert isinstance(proc, subprocess.Popen)
        chunks: list[bytes] = []
        try:
            ready, _, _ = select.select([fd], [], [], timeout)
        except (OSError, ValueError):
            ready = []
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
        if exit_code is not None and not chunks:
            self.close_session(sid)
        return b"".join(chunks).decode("utf-8", errors="replace"), exit_code

    def write(self, sid: str, data: str) -> None:
        if not isinstance(data, str) or len(data.encode("utf-8", errors="replace")) > 65536:
            raise ValueError("Terminal input must be a string up to 64 KiB.")
        with self._lock:
            sess = self._sessions.get(sid)
        if not sess:
            raise KeyError(f"Unknown or closed session: {sid}")
        proc = sess["proc"]
        assert isinstance(proc, subprocess.Popen)
        if proc.poll() is not None:
            raise BrokenPipeError(f"Session has already exited: {sid}")
        os.write(int(sess["fd"]), data.encode("utf-8", errors="replace"))

    def resize(self, sid: str, cols: int, rows: int) -> None:
        with self._lock:
            sess = self._sessions.get(sid)
        if not sess:
            raise KeyError(f"Unknown or closed session: {sid}")
        proc = sess["proc"]
        assert isinstance(proc, subprocess.Popen)
        if proc.poll() is not None:
            raise BrokenPipeError(f"Session has already exited: {sid}")
        self._set_winsize(int(sess["fd"]), cols, rows)

    def interrupt(self, sid: str) -> None:
        with self._lock:
            sess = self._sessions.get(sid)
        if not sess:
            raise KeyError(f"Unknown or closed session: {sid}")
        proc = sess["proc"]
        assert isinstance(proc, subprocess.Popen)
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGINT)
            except ProcessLookupError as err:
                raise BrokenPipeError(f"Session process no longer running: {sid}") from err

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


def default_runtime_file() -> Path | None:
    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not xdg_runtime:
        return None
    base = Path(xdg_runtime)
    try:
        st = base.stat()
    except OSError:
        return None
    if not base.is_dir() or st.st_uid != os.geteuid():
        return None
    return base / "nexus-os" / "system-bridge.json"


def write_runtime_file(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    tmp_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(payload))
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, path)
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def serve_loopback(port: int, runtime_file: Path | None = None) -> None:
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
            bound_port = self.server.server_address[1]
            if origin and origin not in (f"http://127.0.0.1:{bound_port}", f"http://localhost:{bound_port}"):
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
            raw_len = self.headers.get("Content-Length", "0")
            try:
                length = int(raw_len)
            except ValueError as err:
                raise ValueError("Invalid Content-Length header") from err
            if length <= 0:
                return {}
            if length > 65536:
                raise ValueError("Request body exceeds 64 KiB limit")
            parsed = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(parsed, dict):
                raise ValueError("JSON body must be an object")
            return parsed

        def _run_cli_json(self, cmd: list[str], timeout: float = 10.0) -> None:
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=timeout)
                payload = json.loads(proc.stdout)
            except subprocess.TimeoutExpired:
                self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": f"Helper timed out after {timeout}s"})
                return
            except FileNotFoundError as err:
                self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                return
            except subprocess.CalledProcessError as err:
                msg = (err.stderr or err.stdout or str(err)).strip()
                self._send_json(HTTPStatus.BAD_GATEWAY, {"error": msg})
                return
            except json.JSONDecodeError:
                self._send_json(HTTPStatus.BAD_GATEWAY, {"error": "Helper returned malformed JSON output"})
                return
            self._send_json(HTTPStatus.OK, payload)

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            if not self._authorized():
                self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid X-Nexus-Token"})
                return
            if parsed.path == "/api/telemetry":
                self._send_json(HTTPStatus.OK, collect_telemetry_snapshot())
            elif parsed.path == "/api/security/status":
                try:
                    cmd = resolve_helper("linux/mint/nexus-security-cli.sh", "nexus-security-cli") + ["status"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd)
            elif parsed.path == "/api/gaming/status":
                try:
                    cmd = resolve_helper("linux/mint/nexus-gaming-cli.sh", "nexus-gaming-cli") + ["status"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd)
            elif parsed.path == "/api/installer/preflight":
                try:
                    cmd = resolve_helper("linux/installer/nexus-install-preflight.sh", "nexus-install-preflight")
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd)
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
            try:
                body = self._read_json()
            except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as err:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"Invalid JSON request: {err}"})
                return

            if self.path == "/api/terminal/open":
                try:
                    cols = int(body.get("cols", 80))
                    rows = int(body.get("rows", 24))
                    sid = pty_mgr.open_session(cols, rows)
                    self._send_json(HTTPStatus.OK, {"sessionId": sid})
                except (TypeError, ValueError) as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
                except RuntimeError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
            elif self.path == "/api/terminal/write":
                try:
                    pty_mgr.write(str(body.get("sessionId", "")), body.get("data"))
                    self._send_json(HTTPStatus.OK, {"ok": True})
                except KeyError as err:
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": str(err)})
                except (BrokenPipeError, OSError) as err:
                    self._send_json(HTTPStatus.GONE, {"error": str(err)})
                except ValueError as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif self.path == "/api/terminal/resize":
                try:
                    pty_mgr.resize(str(body.get("sessionId", "")), int(body.get("cols", 80)), int(body.get("rows", 24)))
                    self._send_json(HTTPStatus.OK, {"ok": True})
                except KeyError as err:
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": str(err)})
                except (BrokenPipeError, OSError) as err:
                    self._send_json(HTTPStatus.GONE, {"error": str(err)})
                except (TypeError, ValueError) as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif self.path == "/api/terminal/interrupt":
                try:
                    pty_mgr.interrupt(str(body.get("sessionId", "")))
                    self._send_json(HTTPStatus.OK, {"ok": True})
                except KeyError as err:
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": str(err)})
                except (BrokenPipeError, OSError) as err:
                    self._send_json(HTTPStatus.GONE, {"error": str(err)})
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
                try:
                    cmd = resolve_helper("linux/mint/nexus-gaming-cli.sh", "nexus-gaming-cli") + ["gaming-mode", mode_action]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10.0)
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Gaming mode helper timed out"})
                    return
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.INTERNAL_SERVER_ERROR,
                    {"ok": proc.returncode == 0, "message": proc.stdout.strip() or proc.stderr.strip()},
                )
            elif self.path == "/api/personalisation/apply":
                try:
                    cmd = resolve_personalisation_cmd(body)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                try:
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15.0)
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Personalisation apply timed out"})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "output": (proc.stdout + proc.stderr).strip()},
                )
            else:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "Unknown API endpoint"})

    server = ThreadingHTTPServer(("127.0.0.1", port), BridgeHandler)
    actual_port = server.server_address[1]
    ready_payload = {"url": f"http://127.0.0.1:{actual_port}", "token": token, "pid": os.getpid()}
    active_runtime_file = runtime_file if runtime_file is not None else default_runtime_file()
    if active_runtime_file is not None:
        write_runtime_file(active_runtime_file, ready_payload)

    def handle_stop(signum: int, frame: object) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    prev_sigterm = signal.getsignal(signal.SIGTERM)
    signal.signal(signal.SIGTERM, handle_stop)
    print(json.dumps({"url": f"http://127.0.0.1:{actual_port}", "token": token}), flush=True)
    try:
        server.serve_forever()
    finally:
        signal.signal(signal.SIGTERM, prev_sigterm)
        pty_mgr.close_all()
        server.server_close()
        if active_runtime_file is not None:
            try:
                active_runtime_file.unlink(missing_ok=True)
            except OSError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser(description="NEXUS OS Linux Mint local system bridge")
    parser.add_argument("--telemetry", action="store_true", help="Print real /proc + sysfs telemetry JSON")
    parser.add_argument("--tools", action="store_true", help="Print detected Linux Mint desktop tools JSON")
    parser.add_argument("--bash-check", action="store_true", help="Verify real GNU Bash PTY open/write/read/close")
    parser.add_argument("--serve", action="store_true", help="Run loopback-only authenticated local bridge API")
    parser.add_argument("--port", type=int, default=0, help="Loopback port for --serve (default: ephemeral)")
    parser.add_argument("--runtime-file", type=Path, default=None, help="Optional 0600 JSON runtime file path for --serve")
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
        serve_loopback(args.port, runtime_file=args.runtime_file)
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
