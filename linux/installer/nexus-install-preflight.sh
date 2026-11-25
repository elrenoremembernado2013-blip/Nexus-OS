#!/usr/bin/env bash
# Read-only hardware, firmware, storage, and Ubiquity installer readiness probe
# for NEXUS OS (Linux Mint 22.3 / Ubuntu Noble live/installed environments).
# Never alters partitions, disks, or system state.
set -euo pipefail

FORMAT="json"

usage() {
  cat <<'USAGE'
Usage: bash linux/installer/nexus-install-preflight.sh [OPTIONS]

Reports real hardware, firmware (UEFI/BIOS), block storage, network, audio,
battery, and Linux Mint Ubiquity installer availability. Read-only.

Options:
  --summary   Print human-readable preflight summary instead of JSON
  --help, -h  Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --summary) FORMAT="summary"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$FORMAT" <<'PY'
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

fmt = sys.argv[1]

def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None

arch = platform.machine()
firmware = "UEFI" if Path("/sys/firmware/efi").is_dir() else "BIOS/Legacy (or container)"

cpu = "unavailable"
cpuinfo = read_text(Path("/proc/cpuinfo"))
if cpuinfo:
    for line in cpuinfo.splitlines():
        if line.lower().startswith("model name"):
            cpu = line.split(":", 1)[1].strip()
            break

ram_total_mib = None
meminfo = read_text(Path("/proc/meminfo"))
if meminfo:
    for line in meminfo.splitlines():
        if line.startswith("MemTotal:"):
            tok = line.split(":", 1)[1].strip().split()[0]
            if tok.isdigit():
                ram_total_mib = round(int(tok) / 1024)
            break

root_free_gib = None
try:
    st = os.statvfs("/")
    root_free_gib = round((st.f_bavail * st.f_frsize) / (1024 ** 3), 1)
except OSError:
    pass

# Block disks via lsblk if available (read-only)
disks = []
if shutil.which("lsblk"):
    try:
        res = subprocess.run(
            ["lsblk", "-J", "-d", "-o", "NAME,SIZE,MODEL,TYPE,RO,RM"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)
            for dev in data.get("blockdevices", []):
                if dev.get("type") == "disk":
                    disks.append({
                        "device": f"/dev/{dev.get('name')}",
                        "size": dev.get("size"),
                        "model": (dev.get("model") or "").strip() or "Unknown",
                        "removable": bool(dev.get("rm")),
                    })
    except Exception:
        pass

gpus = []
for dev in sorted(Path("/sys/bus/pci/devices").glob("*")):
    cls = read_text(dev / "class") or ""
    if cls.startswith("0x03"):
        drv_link = dev / "driver"
        gpus.append({
            "slot": dev.name,
            "vendor": read_text(dev / "vendor") or "unknown",
            "device": read_text(dev / "device") or "unknown",
            "driver": drv_link.resolve().name if drv_link.is_symlink() else "none",
        })

network_ifaces = []
for iface in sorted(Path("/sys/class/net").iterdir()):
    if iface.name == "lo":
        continue
    state = read_text(iface / "operstate") or "unknown"
    network_ifaces.append({"name": iface.name, "state": state})

audio_cards = []
asound = read_text(Path("/proc/asound/cards"))
if asound:
    for line in asound.splitlines():
        if line and line[0].strip().isdigit() and ":" in line:
            audio_cards.append(line.strip())

displays = []
for conn in sorted(Path("/sys/class/drm").glob("card*-*")):
    status = read_text(conn / "status")
    if status == "connected":
        displays.append(conn.name)

battery = None
for bat in sorted(Path("/sys/class/power_supply").glob("BAT*")):
    cap = read_text(bat / "capacity")
    status = read_text(bat / "status")
    battery = {"name": bat.name, "capacity": int(cap) if cap and cap.isdigit() else None, "status": status or "unknown"}
    break

ubiquity_path = shutil.which("ubiquity")
live_session = Path("/rofs").is_dir() or Path("/cdrom/casper/filesystem.squashfs").is_file()

warnings = []
if arch != "x86_64":
    warnings.append(f"Unsupported architecture ({arch}); NEXUS OS targets x86_64.")
if ram_total_mib is not None and ram_total_mib < 2048:
    warnings.append(f"Low RAM ({ram_total_mib} MiB); at least 2048 MiB (4096 MiB recommended) is required.")
if not ubiquity_path:
    warnings.append("Linux Mint Ubiquity installer binary is not present on this host (live ISO required to install).")

payload = {
    "arch": arch,
    "firmware": firmware,
    "live_session": live_session,
    "ubiquity_available": ubiquity_path is not None,
    "ubiquity_path": ubiquity_path,
    "hardware": {
        "cpu": cpu,
        "ram_total_mib": ram_total_mib,
        "root_free_gib": root_free_gib,
        "disks": disks,
        "gpus": gpus,
        "network": network_ifaces,
        "audio_cards": audio_cards,
        "displays": displays,
        "battery": battery,
    },
    "requirements": {
        "min_ram_mib": 2048,
        "recommended_ram_mib": 4096,
        "min_storage_gib": 20,
        "recommended_storage_gib": 32,
        "arch": "x86_64",
    },
    "warnings": warnings,
}

if fmt == "summary":
    print(f"NEXUS OS Install Preflight ({payload['arch']} / {payload['firmware']})")
    print(f"  CPU: {cpu}")
    print(f"  RAM: {ram_total_mib} MiB (min {payload['requirements']['min_ram_mib']} MiB)")
    print(f"  Disks detected: {len(disks)}")
    print(f"  Ubiquity installer: {'available' if payload['ubiquity_available'] else 'unavailable'}")
    for w in warnings:
        print(f"  [WARN] {w}")
else:
    print(json.dumps(payload, indent=2))
PY
