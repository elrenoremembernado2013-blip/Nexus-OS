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
import base64
import binascii
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
import stat
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
_UID_NAME_CACHE: dict[int, str] = {}
_LAST_CPU_SAMPLE: tuple[int, int] | None = None
_CPU_LOCK = threading.Lock()

ALLOWLISTED_TOOLS: dict[str, list[list[str]]] = {
    "files": [["nemo"], ["pcmanfm-qt"], ["pcmanfm"], ["thunar"], ["xdg-open", str(Path.home())]],
    "browser": [["firefox"], ["chromium"], ["chromium-browser"], ["falkon"], ["x-www-browser"]],
    "terminal": [["qterminal"], ["lxterminal"], ["gnome-terminal"], ["xfce4-terminal"], ["x-terminal-emulator"]],
    "monitor": [["gnome-system-monitor"], ["qps"], ["lxtask"], ["xfce4-taskmanager"], ["mate-system-monitor"]],
    "settings": [["cinnamon-settings"], ["xfce4-settings-manager"], ["lxqt-config"], ["obconf"]],
    "display": [["cinnamon-settings", "display"], ["xfce4-display-settings"], ["lxqt-config-monitor"], ["lxrandr"], ["arandr"]],
    "sound": [["cinnamon-settings", "sound"], ["pavucontrol-qt"], ["pavucontrol"]],
    "network": [["cinnamon-settings", "network"], ["nm-connection-editor"]],
    "bluetooth": [["cinnamon-settings", "bluetooth"], ["blueman-manager"]],
    "power": [["cinnamon-settings", "power"], ["xfce4-power-manager-settings"], ["lxqt-config-power"]],
    "accounts": [["cinnamon-settings", "users"], ["users-admin"], ["lxqt-admin-user"]],
    "privacy-security": [["cinnamon-settings", "privacy"], ["gufw"]],
    "packages": [["mintinstall"], ["mintupdate"], ["synaptic"]],
    "updates": [["mintupdate"]],
    "wallpaper": [["cinnamon-settings", "backgrounds"], ["xfdesktop-settings"], ["pcmanfm-qt", "--desktop-pref"], ["nitrogen"]],
    "gaming": [["steam"]],
    "installer": [["nexus-installer-launcher"], ["ubiquity"]],
}

TOOL_INSTALL_HINTS: dict[str, str] = {
    "files": "install nemo, thunar, pcmanfm, or pcmanfm-qt",
    "browser": "install firefox or falkon via NEXUS Store",
    "terminal": "install qterminal, lxterminal, gnome-terminal, or xfce4-terminal",
    "monitor": "install gnome-system-monitor, xfce4-taskmanager, lxtask, or qps",
    "settings": "install xfce4-settings, lxqt-config, or obconf",
    "display": "install arandr, lxrandr, or lxqt-config",
    "sound": "install pavucontrol or pavucontrol-qt",
    "network": "install network-manager-gnome (nm-connection-editor)",
    "bluetooth": "install blueman (blueman-manager)",
    "power": "install xfce4-power-manager or lxqt-powermanagement",
    "accounts": "install gnome-system-tools (users-admin) or lxqt-admin",
    "privacy-security": "install gufw for graphical firewall management",
    "packages": "use nexus-store-cli in a terminal or install mintinstall",
    "updates": "install mintupdate or run apt-get upgrade in terminal",
    "wallpaper": "install xfdesktop4, pcmanfm-qt, or nitrogen",
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
    global _LAST_CPU_SAMPLE

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

    if proc_root == Path("/proc"):
        with _CPU_LOCK:
            cur = parse_stat()
            if not cur:
                return None
            prev = _LAST_CPU_SAMPLE
            _LAST_CPU_SAMPLE = cur
            if prev and cur[1] > prev[1]:
                idle_delta = cur[0] - prev[0]
                total_delta = cur[1] - prev[1]
                usage = 100.0 * (1.0 - (idle_delta / total_delta))
                return round(max(0.0, min(100.0, usage)), 1)

    first = parse_stat()
    if not first:
        return None
    time.sleep(sample_seconds)
    second = parse_stat()
    if not second:
        return None
    if proc_root == Path("/proc"):
        with _CPU_LOCK:
            _LAST_CPU_SAMPLE = second
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
    swap_total_kb = values.get("SwapTotal", 0)
    swap_free_kb = values.get("SwapFree", 0)
    swap_used_kb = max(0, swap_total_kb - swap_free_kb)
    return {
        "total_mib": round(total_kb / 1024),
        "used_mib": round(used_kb / 1024),
        "available_mib": round(avail_kb / 1024),
        "percent": round((used_kb / total_kb) * 100.0, 1),
        "swap_total_mib": round(swap_total_kb / 1024),
        "swap_used_mib": round(swap_used_kb / 1024),
        "swap_percent": round((swap_used_kb / swap_total_kb) * 100.0, 1) if swap_total_kb > 0 else 0.0,
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
            cached = _UID_NAME_CACHE.get(uid)
            if cached is not None:
                user = cached
            else:
                try:
                    user = pwd.getpwuid(uid).pw_name
                except KeyError:
                    pass
                if len(_UID_NAME_CACHE) < 256:
                    _UID_NAME_CACHE[uid] = user
        procs.append({"pid": pid, "name": name, "user": user, "rss_mib": round(rss_kb / 1024, 1)})
    procs.sort(key=lambda p: float(p["rss_mib"]), reverse=True)
    return procs[:limit]


def read_gpu_telemetry(sys_root: Path = Path("/sys")) -> dict[str, object] | None:
    pci_dir = sys_root / "bus" / "pci" / "devices"
    try:
        devs = sorted(pci_dir.glob("*"))
    except OSError:
        return None
    for dev in devs:
        cls = read_text(dev / "class") or ""
        if not cls.startswith("0x03"):
            continue
        drv_link = dev / "driver"
        drv = drv_link.resolve().name if drv_link.is_symlink() else "none"
        busy_raw = read_text(dev / "gpu_busy_percent")
        busy = int(busy_raw) if (busy_raw and busy_raw.isdigit()) else None
        return {"driver": drv, "busy_percent": busy}
    return None


def read_uptime_seconds(proc_root: Path = Path("/proc")) -> int | None:
    raw = read_text(proc_root / "uptime")
    if not raw:
        return None
    try:
        return round(float(raw.split()[0]))
    except (ValueError, IndexError):
        return None


def read_disk_io_mib(proc_root: Path = Path("/proc")) -> dict[str, float] | None:
    raw = read_text(proc_root / "diskstats")
    if not raw:
        return None
    read_sec = 0
    write_sec = 0
    for line in raw.splitlines():
        cols = line.split()
        if len(cols) >= 10:
            name = cols[2]
            if re.fullmatch(r"(sd[a-z]+|nvme\d+n\d+|vd[a-z]+|mmcblk\d+)", name):
                if cols[5].isdigit():
                    read_sec += int(cols[5])
                if cols[9].isdigit():
                    write_sec += int(cols[9])
    return {
        "read_mib": round((read_sec * 512) / (1024 * 1024), 1),
        "write_mib": round((write_sec * 512) / (1024 * 1024), 1),
    }


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
    gpu = read_gpu_telemetry(sys_root=sys_root)
    uptime_s = read_uptime_seconds(proc_root=proc_root)
    disk_io = read_disk_io_mib(proc_root=proc_root)

    return {
        "processor": {
            "summary": f"{cpu_pct}% used" if cpu_pct is not None else "Unavailable",
            "detail": f"Load avg (1m): {load_1m}" if load_1m else "CPU telemetry unavailable",
            "percent": cpu_pct,
        },
        "memory": {
            "summary": f"{mem['used_mib']} / {mem['total_mib']} MiB ({mem['percent']}%)" if mem else "Unavailable",
            "detail": f"{mem['available_mib']} MiB available · Swap {mem['swap_used_mib']}/{mem['swap_total_mib']} MiB" if mem else "Memory telemetry unavailable",
            "percent": mem["percent"] if mem else None,
            "swap_percent": mem["swap_percent"] if mem else None,
            "swap_used_mib": mem["swap_used_mib"] if mem else None,
            "swap_total_mib": mem["swap_total_mib"] if mem else None,
        },
        "storage": {
            "summary": f"{storage['used_gib']} / {storage['total_gib']} GiB" if storage else "Unavailable",
            "detail": (
                f"{storage['available_gib']} GiB free on {storage_mount}"
                + (f" · IO {disk_io['read_mib']}R/{disk_io['write_mib']}W MiB" if disk_io else "")
            ) if storage else "Storage telemetry unavailable",
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
            "celsius": temp["celsius"] if temp else None,
        },
        "gpu": gpu,
        "uptime_seconds": uptime_s,
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


def _append_common_personalisation_flags(
    cmd: list[str],
    body: dict[str, object],
    *,
    allow_panel_autohide: bool = False,
    allow_appearance: bool = False,
) -> None:
    if body.get("theme") in ("midnight", "nebula", "arctic", "emerald", "solar"):
        cmd.extend(["--theme", str(body["theme"])])
    if isinstance(body.get("accent"), str) and re.fullmatch(r"#[0-9a-fA-F]{6}", body["accent"]):
        cmd.extend(["--accent", body["accent"]])
    if allow_appearance and body.get("appearance") in ("dark", "light"):
        cmd.extend(["--appearance", str(body["appearance"])])
    wp_url = body.get("wallpaperUrl")
    if isinstance(wp_url, str) and wp_url.startswith("https://") and len(wp_url) <= 512 and not any(c.isspace() for c in wp_url):
        cmd.extend(["--wallpaper-url", wp_url])
    if body.get("wallpaperFit") in ("zoom", "scaled", "stretched", "centered", "wallpaper"):
        cmd.extend(["--wallpaper-fit", str(body["wallpaperFit"])])
    if isinstance(body.get("workspaces"), int) and 1 <= body["workspaces"] <= 8:
        cmd.extend(["--workspaces", str(body["workspaces"])])
    if allow_panel_autohide and body.get("panelAutohide") in ("false", "true", "intel"):
        cmd.extend(["--panel-autohide", str(body["panelAutohide"])])


def resolve_personalisation_cmd(body: dict[str, object]) -> list[str]:
    edition = str(body.get("edition") or "").strip().lower() or detect_desktop_edition()
    if edition == "xfce":
        cmd = resolve_helper("linux/mint/apply-nexus-xfce.sh", "nexus-apply-xfce")
        if body.get("dryRun"):
            cmd.append("--dry-run")
        if body.get("revert"):
            cmd.append("--revert")
        else:
            if body.get("effectLevel") == "off" or body.get("presetProfile") in ("minimal", "lightweight", "gaming"):
                cmd.append("--lightweight")
            _append_common_personalisation_flags(cmd, body, allow_panel_autohide=True, allow_appearance=True)
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
            _append_common_personalisation_flags(cmd, body, allow_appearance=True)
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
            _append_common_personalisation_flags(cmd, body, allow_appearance=True)
        return cmd

    cmd = resolve_helper("linux/cinnamon/apply-nexus-cinnamon.sh", "nexus-apply-cinnamon")
    if body.get("dryRun"):
        cmd.append("--dry-run")
    if body.get("revert"):
        cmd.append("--revert")
    else:
        _append_common_personalisation_flags(cmd, body, allow_panel_autohide=True, allow_appearance=False)
        if body.get("effectLevel") in ("off", "subtle", "balanced", "enhanced"):
            cmd.extend(["--effect-level", str(body["effectLevel"])])
        if body.get("dockPosition") in ("bottom", "left", "right"):
            cmd.extend(["--dock-position", str(body["dockPosition"])])
        if body.get("panelSize") in ("small", "medium", "large"):
            cmd.extend(["--panel-size", str(body["panelSize"])])
        if body.get("presetProfile") in ("default", "minimal", "gaming", "productivity", "cinematic", "lightweight"):
            cmd.extend(["--preset-profile", str(body["presetProfile"])])
    return cmd


def _resolve_display_env() -> dict[str, str] | None:
    env = dict(os.environ)
    if env.get("DISPLAY") or env.get("WAYLAND_DISPLAY"):
        return env

    xdg_runtime = env.get("XDG_RUNTIME_DIR", "").strip()
    if xdg_runtime and shutil.which("systemctl"):
        try:
            proc = subprocess.run(
                ["systemctl", "--user", "show-environment"],
                capture_output=True,
                text=True,
                timeout=2.0,
            )
            if proc.returncode == 0:
                for line in proc.stdout.splitlines():
                    if line.startswith(("DISPLAY=", "WAYLAND_DISPLAY=", "XAUTHORITY=")):
                        key, val = line.split("=", 1)
                        if val:
                            env[key] = val
        except (OSError, subprocess.SubprocessError):
            pass

    if env.get("DISPLAY") or env.get("WAYLAND_DISPLAY"):
        return env

    uid = os.geteuid()
    if xdg_runtime:
        rt_dir = Path(xdg_runtime)
        try:
            if rt_dir.is_dir() and rt_dir.stat().st_uid == uid:
                for sock in sorted(rt_dir.glob("wayland-*")):
                    try:
                        if stat.S_ISSOCK(sock.stat().st_mode):
                            env["WAYLAND_DISPLAY"] = sock.name
                            return env
                    except OSError:
                        continue
        except OSError:
            pass

    x11_sock_dir = Path("/tmp/.X11-unix")
    xauth = Path.home() / ".Xauthority"
    if x11_sock_dir.is_dir() and xauth.is_file():
        try:
            if xauth.stat().st_uid == uid:
                for sock in sorted(x11_sock_dir.glob("X*")):
                    suffix = sock.name[1:]
                    if not suffix.isdigit():
                        continue
                    try:
                        if stat.S_ISSOCK(sock.stat().st_mode):
                            env["DISPLAY"] = f":{suffix}"
                            env.setdefault("XAUTHORITY", str(xauth))
                            return env
                    except OSError:
                        continue
        except OSError:
            pass

    return None


def launch_allowlisted_tool(category: str) -> dict[str, object]:
    candidates = ALLOWLISTED_TOOLS.get(category)
    if not candidates:
        return {"ok": False, "message": f"Unknown tool category: {category}"}
    for cmd in candidates:
        if shutil.which(cmd[0]):
            launch_env = _resolve_display_env()
            if launch_env is None:
                return {
                    "ok": False,
                    "command": cmd[0],
                    "message": f"Cannot launch {cmd[0]}: no active X11 or Wayland display session.",
                }
            try:
                subprocess.Popen(cmd, env=launch_env, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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


class SafeHomeFilesManager:
    """Strict $HOME-jailed file browser & safe manipulation helper for NEXUS Files."""

    PROTECTED_TOP_DIRS = frozenset({".ssh", ".gnupg", ".pki", ".aws", ".kube"})
    MAX_PREVIEW_BYTES = 262144

    def __init__(self, home_root: Path | None = None) -> None:
        self.home_root = (home_root or Path.home()).resolve()

    def _resolve_in_home(self, rel_or_abs: str | None, *, allow_root: bool = False) -> Path:
        raw = (rel_or_abs or "").strip()
        if not raw or raw == "~":
            target = self.home_root
        elif raw.startswith("~/"):
            target = self.home_root / raw[2:]
        else:
            p = Path(raw)
            target = p if p.is_absolute() else (self.home_root / p)

        resolved = target.resolve(strict=False)
        try:
            rel = resolved.relative_to(self.home_root)
        except ValueError as err:
            raise PermissionError("Access denied: path is outside the user's home directory.") from err

        if not allow_root and resolved == self.home_root:
            raise PermissionError("Refusing to modify or delete the user home directory root.")

        parts = rel.parts
        if parts and parts[0] in self.PROTECTED_TOP_DIRS:
            raise PermissionError(f"Access denied: protected security directory ({parts[0]}) is never exposed.")
        return resolved

    @staticmethod
    def _validate_entry_name(name: str) -> str:
        clean = str(name or "").strip()
        if not clean or clean in (".", "..") or "/" in clean or "\\" in clean or "\x00" in clean:
            raise ValueError("Entry name must be non-empty and cannot contain path separators.")
        if clean in SafeHomeFilesManager.PROTECTED_TOP_DIRS:
            raise PermissionError(f"Name {clean} is reserved for system security credentials.")
        return clean

    def list_dir(self, path_arg: str | None = None) -> dict[str, object]:
        target = self._resolve_in_home(path_arg, allow_root=True)
        if not target.is_dir():
            raise FileNotFoundError(f"Not a readable directory: {target}")
        entries = []
        for child in sorted(target.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower())):
            try:
                rel_child = child.resolve(strict=False).relative_to(self.home_root)
            except ValueError:
                continue
            if rel_child.parts and rel_child.parts[0] in self.PROTECTED_TOP_DIRS:
                continue
            try:
                st = child.lstat()
                kind = "directory" if stat.S_ISDIR(st.st_mode) else "file"
                entries.append({
                    "name": child.name,
                    "path": str(child),
                    "relPath": str(rel_child),
                    "kind": kind,
                    "size": 0 if kind == "directory" else st.st_size,
                    "modified": int(st.st_mtime * 1000),
                    "mode": stat.filemode(st.st_mode),
                })
            except OSError:
                continue
        sv = os.statvfs(target)
        free_gib = round((sv.f_bavail * sv.f_frsize) / (1024 ** 3), 1)
        rel_cur = target.relative_to(self.home_root)
        return {
            "home": str(self.home_root),
            "path": str(target),
            "relPath": "." if str(rel_cur) == "." else str(rel_cur),
            "free_gib": free_gib,
            "entries": entries[:500],
        }

    def preview_file(self, path_arg: str) -> dict[str, object]:
        target = self._resolve_in_home(path_arg, allow_root=False)
        if not target.is_file():
            raise FileNotFoundError("Preview is only supported on regular files inside your home folder.")
        st = target.stat()
        if st.st_size > self.MAX_PREVIEW_BYTES:
            return {"name": target.name, "size": st.st_size, "tooLarge": True, "text": None}
        raw = target.read_bytes()
        if b"\x00" in raw:
            return {"name": target.name, "size": st.st_size, "binary": True, "text": None}
        return {"name": target.name, "size": st.st_size, "binary": False, "text": raw.decode("utf-8", errors="replace")}

    def mkdir(self, parent_arg: str | None, name: str) -> dict[str, object]:
        parent = self._resolve_in_home(parent_arg, allow_root=True)
        clean = self._validate_entry_name(name)
        new_dir = parent / clean
        if new_dir.exists():
            raise FileExistsError(f"“{clean}” already exists here.")
        new_dir.mkdir(parents=False, exist_ok=False)
        return {"ok": True, "path": str(new_dir), "name": clean}

    def touch(self, parent_arg: str | None, name: str) -> dict[str, object]:
        parent = self._resolve_in_home(parent_arg, allow_root=True)
        clean = self._validate_entry_name(name)
        new_file = parent / clean
        if new_file.exists():
            raise FileExistsError(f"“{clean}” already exists here.")
        new_file.write_text("", encoding="utf-8")
        return {"ok": True, "path": str(new_file), "name": clean}

    def rename(self, path_arg: str, new_name: str) -> dict[str, object]:
        target = self._resolve_in_home(path_arg, allow_root=False)
        clean = self._validate_entry_name(new_name)
        dest = target.parent / clean
        self._resolve_in_home(str(dest), allow_root=False)
        if dest.exists():
            raise FileExistsError(f"“{clean}” already exists here.")
        target.rename(dest)
        return {"ok": True, "path": str(dest), "name": clean}

    def remove(self, path_arg: str) -> dict[str, object]:
        target = self._resolve_in_home(path_arg, allow_root=False)
        if target.relative_to(self.home_root).parts[:2] == (".config", "nexus-os"):
            raise PermissionError("Protected NEXUS desktop config directory cannot be removed from File Manager.")
        if target.is_dir() and not target.is_symlink():
            shutil.rmtree(target)
        else:
            target.unlink()
        return {"ok": True, "removed": str(target)}


def quantum_notes_path(data_home: Path | None = None) -> Path:
    base = data_home or Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share"))
    return base / "nexus-os" / "quantum-notes.json"


def read_quantum_notes(data_home: Path | None = None) -> dict[str, object]:
    p = quantum_notes_path(data_home)
    if not p.is_file():
        return {"path": str(p), "notes": []}
    try:
        parsed = json.loads(p.read_text(encoding="utf-8"))
        notes = parsed if isinstance(parsed, list) else parsed.get("notes", [])
        if not isinstance(notes, list):
            notes = []
    except (OSError, json.JSONDecodeError):
        notes = []
    return {"path": str(p), "notes": notes[:200]}


def write_quantum_notes(notes: object, data_home: Path | None = None) -> dict[str, object]:
    if not isinstance(notes, list):
        raise ValueError("notes must be a list")
    cleaned = []
    for item in notes[:200]:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()[:120]
        body = str(item.get("body") or "").strip()[:8000]
        track = str(item.get("track") or "general").strip()[:40]
        nid = str(item.get("id") or secrets.token_hex(6)).strip()[:40]
        updated = str(item.get("updatedAt") or "")[:40]
        if title or body:
            cleaned.append({"id": nid, "title": title or "Untitled note", "body": body, "track": track, "updatedAt": updated})
    p = quantum_notes_path(data_home)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({"notes": cleaned}, indent=2), encoding="utf-8")
    return {"ok": True, "path": str(p), "count": len(cleaned), "notes": cleaned}


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
    files_mgr = SafeHomeFilesManager()

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
            if length > 12 * 1024 * 1024:
                raise ValueError("Request body exceeds 12 MiB limit")
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
            elif parsed.path == "/api/control-centre":
                try:
                    cmd = resolve_helper("linux/mint/nexus-control-centre-cli.sh", "nexus-control-centre") + ["status", "--json"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=6.0)
            elif parsed.path == "/api/wallpapers":
                try:
                    cmd = resolve_helper("linux/mint/nexus-wallpaper-cli.sh", "nexus-wallpaper") + ["list", "--json"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=6.0)
            elif parsed.path == "/api/store/sources":
                try:
                    cmd = resolve_helper("linux/mint/nexus-store-cli.sh", "nexus-store-cli") + ["sources"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=6.0)
            elif parsed.path == "/api/store/search":
                qs = urllib.parse.parse_qs(parsed.query)
                query = (qs.get("q") or [""])[0].strip()
                if not query or len(query) > 80:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Search query must be 1-80 characters"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-store-cli.sh", "nexus-store-cli") + ["--json", "search", query]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=12.0)
            elif parsed.path == "/api/store/installed":
                try:
                    cmd = resolve_helper("linux/mint/nexus-store-cli.sh", "nexus-store-cli") + ["--json", "installed"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=10.0)
            elif parsed.path in ("/api/store/updates", "/api/updates/status"):
                try:
                    cmd = resolve_helper("linux/mint/nexus-store-cli.sh", "nexus-store-cli") + ["--json", "updates"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=12.0)
            elif parsed.path == "/api/store/info":
                qs = urllib.parse.parse_qs(parsed.query)
                source = (qs.get("source") or [""])[0].strip()
                pkg = (qs.get("pkg") or [""])[0].strip()
                if source not in ("apt", "flatpak") or not pkg:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid package source or id"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-store-cli.sh", "nexus-store-cli") + ["--json", "info", source, pkg]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=10.0)
            elif parsed.path == "/api/security/status":
                try:
                    cmd = resolve_helper("linux/mint/nexus-security-cli.sh", "nexus-security-cli") + ["status"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd)
            elif parsed.path == "/api/security/permissions":
                qs = urllib.parse.parse_qs(parsed.query)
                app_id = (qs.get("appId") or [""])[0].strip()
                if not re.fullmatch(r"[A-Za-z0-9_.-]{3,128}", app_id) or "." not in app_id:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid Flatpak application ID"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-security-cli.sh", "nexus-security-cli") + ["permissions", app_id]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=8.0)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Permissions query timed out"})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "appId": app_id, "permissions": proc.stdout.strip() or proc.stderr.strip()},
                )
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
            elif parsed.path == "/api/hardware/inventory":
                try:
                    cmd = resolve_helper("linux/hardware/nexus-hw-inventory.sh", "nexus-hw-inventory") + ["--json"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=15.0)
            elif parsed.path == "/api/hardware/diagnostics":
                try:
                    cmd = resolve_helper("linux/hardware/nexus-hw-diagnostics.sh", "nexus-hw-diagnostics") + ["--json"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=18.0)
            elif parsed.path == "/api/recovery/diagnose":
                try:
                    cmd = resolve_helper("linux/installer/nexus-recovery.sh", "nexus-recovery") + ["--diagnose", "--json", "--redacted"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=10.0)
            elif parsed.path == "/api/performance/overview":
                try:
                    cmd = resolve_helper("linux/mint/nexus-performance-cli.sh", "nexus-performance-cli") + ["overview"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=10.0)
            elif parsed.path == "/api/files/list":
                qs = urllib.parse.parse_qs(parsed.query)
                path_arg = (qs.get("path") or [""])[0]
                try:
                    self._send_json(HTTPStatus.OK, files_mgr.list_dir(path_arg))
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": str(err)})
                except OSError as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif parsed.path == "/api/files/preview":
                qs = urllib.parse.parse_qs(parsed.query)
                path_arg = (qs.get("path") or [""])[0]
                try:
                    self._send_json(HTTPStatus.OK, files_mgr.preview_file(path_arg))
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": str(err)})
                except OSError as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif parsed.path == "/api/quantum/notes":
                self._send_json(HTTPStatus.OK, read_quantum_notes())
            elif parsed.path == "/api/compat/status":
                try:
                    cmd = resolve_helper("linux/mint/nexus-compat-cli.sh", "nexus-compat-cli") + ["status"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=10.0)
            elif parsed.path == "/api/compat/catalog":
                try:
                    cmd = resolve_helper("linux/mint/nexus-compat-cli.sh", "nexus-compat-cli") + ["catalog"]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=6.0)
            elif parsed.path == "/api/compat/inspect":
                qs = urllib.parse.parse_qs(parsed.query)
                path_arg = (qs.get("path") or [""])[0]
                try:
                    resolved = files_mgr._resolve_in_home(path_arg, allow_root=False)
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                    return
                except OSError as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
                    return
                if not resolved.is_file():
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": "Target file not found inside home directory"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-compat-cli.sh", "nexus-compat-cli") + ["inspect", str(resolved), resolved.name]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=10.0)
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
            elif self.path == "/api/control-centre/action":
                action_type = str(body.get("type", "")).strip()
                if action_type not in ("volume", "mute", "brightness", "wifi", "bluetooth", "dnd"):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Unsupported control-centre action"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-control-centre-cli.sh", "nexus-control-centre") + ["action", "--type", action_type]
                    val = body.get("value")
                    if val is not None and str(val).strip() != "":
                        cmd.extend(["--value", str(val).strip()])
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=6.0)
                    payload = json.loads(proc.stdout) if proc.stdout.strip().startswith("{") else {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()}
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Control centre action timed out"})
                    return
                self._send_json(HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST, payload)
            elif self.path == "/api/wallpapers/import":
                encoded = body.get("data")
                mime = str(body.get("mime") or "").strip().lower()
                extensions = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}
                if mime not in extensions or not isinstance(encoded, str) or len(encoded) > 11_200_000:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Provide a JPEG, PNG, or WebP image up to 8 MiB."})
                    return
                try:
                    image_bytes = base64.b64decode(encoded, validate=True)
                except (binascii.Error, ValueError):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Wallpaper image data is not valid base64."})
                    return
                if not image_bytes or len(image_bytes) > 8 * 1024 * 1024:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Wallpaper image must be between 1 byte and 8 MiB."})
                    return
                is_jpeg = image_bytes.startswith(b"\xff\xd8\xff")
                is_png = image_bytes.startswith(b"\x89PNG\r\n\x1a\n")
                is_webp = image_bytes[:4] == b"RIFF" and image_bytes[8:12] == b"WEBP"
                if not ((mime == "image/jpeg" and is_jpeg) or (mime == "image/png" and is_png) or (mime == "image/webp" and is_webp)):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Image content does not match its declared JPEG/PNG/WebP type."})
                    return
                fit = str(body.get("fit") or "zoom").strip()
                if fit not in ("zoom", "scaled", "stretched", "centered", "wallpaper"):
                    fit = "zoom"
                try:
                    target_dir = Path.home() / ".local" / "share" / "nexus-os" / "wallpapers"
                    target_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
                    target = target_dir / ("custom" + extensions[mime])
                    temp_target = target.with_name(target.name + ".part")
                    temp_target.write_bytes(image_bytes)
                    os.chmod(temp_target, 0o600)
                    os.replace(temp_target, target)
                    cmd = resolve_helper("linux/mint/nexus-wallpaper-cli.sh", "nexus-wallpaper") + ["apply", "--file", str(target), "--fit", fit]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15.0)
                    payload = json.loads(proc.stdout) if proc.stdout.strip().startswith("{") else {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()}
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Custom wallpaper apply timed out"})
                    return
                except OSError as err:
                    self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"Could not save custom wallpaper: {err}"})
                    return
                self._send_json(HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST, payload)
            elif self.path == "/api/wallpapers/apply":
                wp_id = str(body.get("id") or "").strip()
                wp_url = str(body.get("url") or "").strip()
                fit = str(body.get("fit") or "zoom").strip()
                if fit not in ("zoom", "scaled", "stretched", "centered", "wallpaper"):
                    fit = "zoom"
                try:
                    cmd = resolve_helper("linux/mint/nexus-wallpaper-cli.sh", "nexus-wallpaper") + ["apply", "--fit", fit]
                    if wp_id and re.fullmatch(r"[a-z0-9-]{1,64}", wp_id):
                        cmd.extend(["--id", wp_id])
                    elif wp_url.startswith("https://") and len(wp_url) <= 512 and not any(c.isspace() for c in wp_url):
                        cmd.extend(["--url", wp_url])
                    else:
                        self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Provide a valid wallpaper id or https:// url"})
                        return
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=20.0)
                    payload = json.loads(proc.stdout) if proc.stdout.strip().startswith("{") else {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()}
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Wallpaper apply timed out"})
                    return
                self._send_json(HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST, payload)
            elif self.path in ("/api/store/install", "/api/store/remove"):
                action = "install" if self.path.endswith("/install") else "remove"
                source = str(body.get("source") or "").strip()
                pkg = str(body.get("pkg") or "").strip()
                if source not in ("apt", "flatpak") or not pkg:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid package source or id"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-store-cli.sh", "nexus-store-cli") + ["--json", action, source, pkg]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180.0)
                    payload = json.loads(proc.stdout) if proc.stdout.strip().startswith("{") else {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()}
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": f"Package {action} timed out"})
                    return
                self._send_json(HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST, payload)
            elif self.path == "/api/security/firewall":
                fw_action = str(body.get("action") or "").strip()
                if fw_action not in ("enable", "disable"):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid firewall action"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-security-cli.sh", "nexus-security-cli") + ["firewall", fw_action]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30.0)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Firewall action timed out"})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()},
                )
            elif self.path == "/api/security/flatpak-revoke":
                app_id = str(body.get("appId") or "").strip()
                flag = str(body.get("flag") or "").strip()
                if not re.fullmatch(r"[A-Za-z0-9_.-]{3,128}", app_id) or "." not in app_id:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid Flatpak appId"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-security-cli.sh", "nexus-security-cli") + ["flatpak-revoke", app_id, flag]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10.0)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()},
                )
            elif self.path == "/api/security/flatpak-reset":
                app_id = str(body.get("appId") or "").strip()
                if not re.fullmatch(r"[A-Za-z0-9_.-]{3,128}", app_id) or "." not in app_id:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid Flatpak appId"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-security-cli.sh", "nexus-security-cli") + ["flatpak-reset", app_id]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10.0)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()},
                )
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
            elif self.path == "/api/performance/low-resource":
                lr_action = str(body.get("action") or "").strip()
                if lr_action not in ("enable", "disable"):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid low-resource action (expected enable or disable)"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-performance-cli.sh", "nexus-performance-cli") + ["low-resource", lr_action]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=12.0)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Low-resource helper timed out"})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()},
                )
            elif self.path == "/api/performance/startup":
                st_action = str(body.get("action") or "").strip()
                desk_id = str(body.get("id") or "").strip()
                if st_action not in ("enable", "disable") or not re.fullmatch(r"[A-Za-z0-9_.-]+\.desktop", desk_id):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid startup action or desktop entry id"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-performance-cli.sh", "nexus-performance-cli") + ["startup", st_action, desk_id]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=8.0)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()},
                )
            elif self.path == "/api/performance/cleanup":
                target = str(body.get("target") or "").strip()
                confirmed = body.get("confirm") is True
                if target not in ("thumbnails", "wallpapers", "mesa", "apt") or not confirmed:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Cleanup requires a valid target and explicit confirm=true"})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-performance-cli.sh", "nexus-performance-cli") + ["cleanup", "--target", target, "--confirm"]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=25.0)
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Cache cleanup timed out"})
                    return
                self._send_json(
                    HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST,
                    {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()},
                )
            elif self.path == "/api/files/mkdir":
                try:
                    self._send_json(HTTPStatus.OK, files_mgr.mkdir(body.get("path"), str(body.get("name") or "")))
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                except (ValueError, FileExistsError, OSError) as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif self.path == "/api/files/touch":
                try:
                    self._send_json(HTTPStatus.OK, files_mgr.touch(body.get("path"), str(body.get("name") or "")))
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                except (ValueError, FileExistsError, OSError) as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif self.path == "/api/files/rename":
                try:
                    self._send_json(HTTPStatus.OK, files_mgr.rename(str(body.get("path") or ""), str(body.get("newName") or "")))
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                except (ValueError, FileNotFoundError, FileExistsError, OSError) as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif self.path == "/api/files/delete":
                try:
                    self._send_json(HTTPStatus.OK, files_mgr.remove(str(body.get("path") or "")))
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                except (FileNotFoundError, OSError) as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif self.path == "/api/quantum/notes":
                try:
                    self._send_json(HTTPStatus.OK, write_quantum_notes(body.get("notes")))
                except ValueError as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
            elif self.path == "/api/compat/prefix/create":
                slug = str(body.get("name") or "").strip()
                if not re.fullmatch(r"[A-Za-z0-9_-]{1,48}", slug):
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Prefix name must be 1-48 alphanumeric, underscore, or hyphen characters."})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-compat-cli.sh", "nexus-compat-cli") + ["prefix", "create", slug]
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                self._run_cli_json(cmd, timeout=6.0)
            elif self.path == "/api/compat/runtime/install":
                rt = str(body.get("runtime") or "").strip()
                confirmed = body.get("confirm") is True
                if rt not in ("wine", "waydroid", "flatpak", "appimage-fuse") or not confirmed:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Runtime install requires a supported runtime id and explicit confirm=true."})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-compat-cli.sh", "nexus-compat-cli") + ["--confirm"]
                    if body.get("forceLowRam") is True:
                        cmd.append("--force-low-ram")
                    cmd.extend(["install-runtime", rt])
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180.0)
                    payload = json.loads(proc.stdout) if proc.stdout.strip().startswith("{") else {"ok": proc.returncode == 0, "message": (proc.stdout + proc.stderr).strip()}
                except FileNotFoundError as err:
                    self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(err)})
                    return
                except subprocess.TimeoutExpired:
                    self._send_json(HTTPStatus.GATEWAY_TIMEOUT, {"error": "Runtime installation timed out"})
                    return
                self._send_json(HTTPStatus.OK if proc.returncode == 0 else HTTPStatus.BAD_REQUEST, payload)
            elif self.path == "/api/compat/launch":
                confirmed = body.get("confirm") is True
                path_arg = str(body.get("path") or "").strip()
                if not confirmed or not path_arg:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Launching external files requires explicit confirm=true and a home path."})
                    return
                try:
                    resolved = files_mgr._resolve_in_home(path_arg, allow_root=False)
                except PermissionError as err:
                    self._send_json(HTTPStatus.FORBIDDEN, {"error": str(err)})
                    return
                if not resolved.is_file():
                    self._send_json(HTTPStatus.NOT_FOUND, {"error": "Target file not found inside home directory."})
                    return
                try:
                    cmd = resolve_helper("linux/mint/nexus-compat-cli.sh", "nexus-compat-cli") + ["--confirm", "launch", str(resolved)]
                    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                    self._send_json(HTTPStatus.OK, {"ok": True, "pid": proc.pid, "path": str(resolved)})
                except (FileNotFoundError, OSError) as err:
                    self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(err)})
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
