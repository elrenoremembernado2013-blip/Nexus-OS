#!/usr/bin/env bash
# Safe, read-only, privacy-preserving live-session hardware diagnostics utility.
# Never flashes firmware, modifies partitions, formats drives, or auto-installs drivers.
# Never uploads data automatically; omits serials, MACs, UUIDs, usernames, and IPs.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
INVENTORY_SH="$SCRIPT_DIR/nexus-hw-inventory.sh"
[[ -x "$INVENTORY_SH" ]] || INVENTORY_SH="/usr/local/bin/nexus-hw-inventory"

MODE="preview"
EXPORT_DIR=""

usage() {
  cat <<'USAGE'
Usage: bash linux/hardware/nexus-hw-diagnostics.sh [OPTIONS]

Runs safe, non-destructive hardware, connectivity, graphics, audio, battery,
display, and missing-firmware diagnostics inside a live or installed session.
Serial numbers, MAC addresses, UUIDs, usernames, and IPs are strictly omitted.

Options:
  --preview       Print human-readable diagnostic preview to stdout (default)
  --json          Print machine-readable redacted diagnostic report
  --export DIR    Write nexus-diagnostics.json & nexus-diagnostics.md into DIR
  --help, -h      Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --preview) MODE="preview"; shift ;;
    --json) MODE="json"; shift ;;
    --export) [[ $# -ge 2 ]] || { echo '--export requires a directory' >&2; exit 2; }; EXPORT_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$MODE" "$EXPORT_DIR" "$INVENTORY_SH" <<'PY'
import datetime
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

mode = sys.argv[1]
export_dir = sys.argv[2]
inv_sh = sys.argv[3]


def redact(text: str) -> str:
    text = re.sub(r"\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", "<REDACTED_MAC>", text)
    text = re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "<REDACTED_UUID>", text)
    text = re.sub(r"/home/[A-Za-z0-9._-]+", "/home/<USER>", text)
    return text


inv = {}
if Path(inv_sh).is_file():
    res = subprocess.run(["bash", inv_sh, "--json"], capture_output=True, text=True, timeout=15)
    if res.returncode == 0 and res.stdout.strip():
        inv = json.loads(res.stdout)

# Connectivity check (no external IP/MAC leakage)
nm_state = "unavailable"
if shutil.which("nmcli"):
    nm_state = subprocess.run(["nmcli", "-t", "-f", "STATE", "general"], capture_output=True, text=True, timeout=5).stdout.strip() or "unknown"

has_default_route = False
route_out = subprocess.run(["ip", "route", "show", "default"], capture_output=True, text=True, timeout=4).stdout if shutil.which("ip") else ""
if route_out.strip():
    has_default_route = True

# RFKill Wi-Fi / Bluetooth block check
rfkill_items = []
if shutil.which("rfkill"):
    rres = subprocess.run(["rfkill", "-J"], capture_output=True, text=True, timeout=4)
    if rres.returncode == 0 and rres.stdout.strip():
        try:
            for item in json.loads(rres.stdout).get("rfkilldevices", []):
                rfkill_items.append({
                    "type": item.get("type"),
                    "soft": item.get("soft"),
                    "hard": item.get("hard"),
                })
        except Exception:
            pass

# Graphics renderer (read-only glxinfo if X11 display is active)
glx_summary = []
if shutil.which("glxinfo"):
    gres = subprocess.run(["glxinfo", "-B"], capture_output=True, text=True, timeout=5)
    if gres.returncode == 0:
        glx_summary = [redact(l) for l in gres.stdout.splitlines()[:10]]

# Audio server & sinks (read-only)
audio_sinks = []
if shutil.which("pactl"):
    pres = subprocess.run(["pactl", "list", "short", "sinks"], capture_output=True, text=True, timeout=4)
    if pres.returncode == 0:
        audio_sinks = [redact(l) for l in pres.stdout.splitlines()[:8]]

# Battery health (sysfs read-only, no serial numbers read)
batteries = []
ps_dir = Path("/sys/class/power_supply")
if ps_dir.is_dir():
    for bat in sorted(ps_dir.glob("BAT*")):
        def r(fn):
            p = bat / fn
            return p.read_text(encoding="utf-8", errors="replace").strip() if p.is_file() else None
        batteries.append({
            "name": bat.name,
            "status": r("status"),
            "capacity_pct": r("capacity"),
            "energy_full_uwh": r("energy_full"),
            "energy_full_design_uwh": r("energy_full_design"),
        })

# Read-only block device I/O error stats from sysfs (no smartctl/disk writes)
block_stats = []
for dev in inv.get("storage", []):
    bname = Path(dev["device"]).name
    stat_file = Path(f"/sys/block/{bname}/stat")
    in_flight = None
    if stat_file.is_file():
        cols = stat_file.read_text(encoding="utf-8", errors="replace").split()
        if len(cols) >= 9:
            in_flight = int(cols[8])
    block_stats.append({"device": dev["device"], "driver": dev["driver"], "in_flight_io": in_flight})

report = {
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "privacy_policy": "Redacted: zero serial numbers, MAC addresses, UUIDs, usernames, or external IPs.",
    "non_destructive": True,
    "connectivity": {
        "networkmanager_state": nm_state,
        "default_route_present": has_default_route,
        "rfkill": rfkill_items,
    },
    "graphics_glx": glx_summary,
    "audio_sinks": audio_sinks,
    "batteries": batteries,
    "storage_readonly_stats": block_stats,
    "inventory": inv,
}

md_lines = [
    "# NEXUS OS Safe Hardware Diagnostics Report",
    "",
    f"- **Generated (UTC):** {report['generated_at_utc']}",
    f"- **Privacy:** {report['privacy_policy']}",
    f"- **NetworkManager:** `{nm_state}` (default route present: `{has_default_route}`)",
    f"- **Graphics (GLX):** " + ("; ".join(glx_summary[:4]) if glx_summary else "No active X11 GLX session"),
    f"- **Audio Sinks:** {len(audio_sinks)} active",
    f"- **Batteries:** {len(batteries)} detected",
    f"- **Missing Firmware Hints:** {len(inv.get('firmware', {}).get('missing_firmware_hints', []))}",
    "",
    "Review this output carefully before sharing. No data is ever uploaded automatically.",
]
md_text = "\n".join(md_lines) + "\n"

if export_dir:
    out_d = Path(export_dir)
    out_d.mkdir(parents=True, exist_ok=True)
    (out_d / "nexus-diagnostics.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (out_d / "nexus-diagnostics.md").write_text(md_text, encoding="utf-8")
    print(f"Exported redacted diagnostics to {out_d}/nexus-diagnostics.{{json,md}}")

if mode == "json":
    print(json.dumps(report, indent=2))
else:
    print(md_text)
PY
