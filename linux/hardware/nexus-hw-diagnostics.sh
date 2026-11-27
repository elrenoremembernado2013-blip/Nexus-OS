#!/usr/bin/env bash
# Safe, read-only, privacy-preserving live-session hardware diagnostics utility.
# Never flashes firmware, modifies partitions, formats drives, triggers suspend, or auto-installs drivers.
# Never records microphone audio; never logs Wi-Fi SSIDs, passwords, serials, MACs, UUIDs, hostnames, usernames, or IPs.
# Never uploads data automatically; requires human privacy review before sharing.
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
display, suspend-capability, and missing-firmware diagnostics inside a live or
installed session. Serial numbers, MAC addresses, UUIDs, Wi-Fi SSIDs, hostnames,
usernames, and external IPs are strictly omitted.

Options:
  --preview              Print human-readable diagnostic preview to stdout (default)
  --json                 Print machine-readable redacted diagnostic report
  --contribute-template  Print anonymized hardware compatibility contribution JSON (review before sharing)
  --export DIR           Write nexus-diagnostics.json, nexus-diagnostics.md, and contribution template into DIR
  --help, -h             Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --preview) MODE="preview"; shift ;;
    --json) MODE="json"; shift ;;
    --contribute-template) MODE="contribute"; shift ;;
    --export) [[ $# -ge 2 ]] || { echo '--export requires a directory' >&2; exit 2; }; EXPORT_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$MODE" "$EXPORT_DIR" "$INVENTORY_SH" <<'PY'
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys

mode = sys.argv[1]
export_dir = sys.argv[2]
inv_sh = sys.argv[3]
hostname = socket.gethostname()
active_user = os.environ.get("USER", "")


def redact(text: str) -> str:
    text = re.sub(r"\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", "<REDACTED_MAC>", text)
    text = re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "<REDACTED_UUID>", text)
    text = re.sub(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "<REDACTED_IP>", text)
    text = re.sub(r"\bfe80:[0-9a-fA-F:]+\b", "<REDACTED_IPV6>", text)
    text = re.sub(r"/home/[A-Za-z0-9._-]+", "/home/<USER>", text)
    if hostname and len(hostname) > 2:
        text = re.sub(rf"\b{re.escape(hostname)}\b", "<REDACTED_HOST>", text)
    if active_user and len(active_user) > 2 and active_user not in ("root", "user", "nexus"):
        text = re.sub(rf"\b{re.escape(active_user)}\b", "<USER>", text)
    return text


def redact_obj(obj):
    if isinstance(obj, str):
        return redact(obj)
    if isinstance(obj, list):
        return [redact_obj(x) for x in obj]
    if isinstance(obj, dict):
        return {k: redact_obj(v) for k, v in obj.items()}
    return obj


inv = {}
if Path(inv_sh).is_file():
    try:
        res = subprocess.run(["bash", inv_sh, "--json"], capture_output=True, text=True, timeout=15)
        if res.returncode == 0 and res.stdout.strip():
            inv = json.loads(res.stdout)
    except Exception:
        inv = {}

# Connectivity check (NEVER queries or logs SSIDs, BSSIDs, passwords, MACs, or IPs)
nm_state = "unavailable"
wifi_scan_capable = False
if shutil.which("nmcli"):
    try:
        nm_state = subprocess.run(["nmcli", "-t", "-f", "STATE", "general"], capture_output=True, text=True, timeout=5).stdout.strip() or "unknown"
        wres = subprocess.run(["nmcli", "-t", "-f", "WIFI,WIFI-HW", "general"], capture_output=True, text=True, timeout=4)
        if wres.returncode == 0 and "enabled" in wres.stdout.lower():
            wifi_scan_capable = True
    except Exception:
        nm_state = "error"

has_default_route = False
if shutil.which("ip"):
    try:
        route_out = subprocess.run(["ip", "route", "show", "default"], capture_output=True, text=True, timeout=4).stdout
        has_default_route = bool(route_out.strip())
    except Exception:
        pass

# RFKill Wi-Fi / Bluetooth block check
rfkill_items = []
if shutil.which("rfkill"):
    try:
        rres = subprocess.run(["rfkill", "-J"], capture_output=True, text=True, timeout=4)
        if rres.returncode == 0 and rres.stdout.strip():
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
    try:
        gres = subprocess.run(["glxinfo", "-B"], capture_output=True, text=True, timeout=5)
        if gres.returncode == 0:
            glx_summary = [redact(l) for l in gres.stdout.splitlines()[:10]]
    except Exception:
        pass

# Audio server, sinks & service health (read-only metadata; NEVER captures microphone audio)
audio_sinks = []
if shutil.which("pactl"):
    try:
        pres = subprocess.run(["pactl", "list", "short", "sinks"], capture_output=True, text=True, timeout=4)
        if pres.returncode == 0:
            audio_sinks = [redact(l) for l in pres.stdout.splitlines()[:8]]
    except Exception:
        pass

service_states = {}
if shutil.which("systemctl"):
    for unit in ("NetworkManager", "wpa_supplicant", "bluetooth", "upower", "power-profiles-daemon"):
        try:
            sres = subprocess.run(["systemctl", "is-active", unit], capture_output=True, text=True, timeout=2)
            service_states[unit] = (sres.stdout or sres.stderr or "unknown").strip()
        except Exception:
            service_states[unit] = "unknown"
    for uunit in ("pipewire", "pipewire-pulse", "wireplumber", "pulseaudio"):
        try:
            ures = subprocess.run(["systemctl", "--user", "is-active", uunit], capture_output=True, text=True, timeout=2)
            service_states[uunit] = (ures.stdout or ures.stderr or "unknown").strip()
        except Exception:
            service_states[uunit] = "unknown"

# Read-only block device I/O error stats from sysfs (no smartctl/disk writes)
block_stats = []
for dev in inv.get("storage", []):
    bname = Path(dev["device"]).name
    stat_file = Path(f"/sys/block/{bname}/stat")
    in_flight = None
    if stat_file.is_file():
        try:
            cols = stat_file.read_text(encoding="utf-8", errors="replace").split()
            if len(cols) >= 9:
                in_flight = int(cols[8])
        except OSError:
            pass
    block_stats.append({"device": dev["device"], "driver": dev["driver"], "in_flight_io": in_flight})

edition = "unknown"
rel = Path("/etc/nexus-os-release")
if rel.is_file():
    for line in rel.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("NEXUS_EDITION=") or line.startswith("NEXUS_DESKTOP="):
            val = line.split("=", 1)[1].strip().strip('"')
            if val:
                edition = val
                if line.startswith("NEXUS_EDITION="):
                    break

ts_utc = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

report = redact_obj({
    "generated_at_utc": ts_utc,
    "privacy_policy": "Redacted: zero serial numbers, MAC addresses, UUIDs, Wi-Fi SSIDs, hostnames, usernames, or external IPs.",
    "non_destructive": True,
    "connectivity": {
        "networkmanager_state": nm_state,
        "wifi_scan_capable": wifi_scan_capable,
        "default_route_present": has_default_route,
        "rfkill": rfkill_items,
    },
    "service_states": service_states,
    "graphics_glx": glx_summary,
    "graphics_qualification": inv.get("graphics_qualification", {}),
    "audio_sinks": audio_sinks,
    "audio_service_errors": (inv.get("audio") or {}).get("audio_service_errors", []),
    "batteries": (inv.get("power_management") or {}).get("batteries", []),
    "suspend_capabilities": inv.get("suspend_capabilities", {}),
    "secure_boot_chain": inv.get("secure_boot_chain", {}),
    "storage_readonly_stats": block_stats,
    "inventory": inv,
})

# Self-audit serialized JSON for any unredacted PII patterns
raw_check = json.dumps(report)
leaks = []
if re.search(r"\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", raw_check):
    leaks.append("mac_address")
if re.search(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", raw_check):
    leaks.append("uuid")
if re.search(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", raw_check):
    leaks.append("ipv4_address")
if re.search(r"\bfe80:[0-9a-fA-F:]+\b", raw_check):
    leaks.append("ipv6_address")
if re.search(r"/home/(?!<USER>)[A-Za-z0-9._-]+", raw_check):
    leaks.append("home_username")
if hostname and len(hostname) > 2 and re.search(rf"\b{re.escape(hostname)}\b", raw_check):
    leaks.append("hostname")

report["privacy_audit"] = {
    "passed": len(leaks) == 0,
    "detected_unredacted_patterns": leaks,
    "human_review_required_before_sharing": True,
    "auto_upload": False,
}

env_info = inv.get("environment") or {}
gq = inv.get("graphics_qualification") or {}
sb = inv.get("secure_boot_chain") or {}
comp_matrix = inv.get("component_matrix", [])
untested_cats = [c["category"] for c in comp_matrix if c.get("qualification_status") in ("untested", "supported_untested")]
verified_cats = [c["category"] for c in comp_matrix if c.get("qualification_status") == "verified"]

contrib_template = redact_obj({
    "schema_version": 2,
    "submitted_at_utc": ts_utc,
    "privacy_verified": len(leaks) == 0,
    "human_review_required": True,
    "auto_upload": False,
    "nexus_edition": edition,
    "test_environment": env_info.get("label", "bare_metal_user_report"),
    "compatibility_status": {
        "overall": "unverified_bare_metal" if env_info.get("is_virtual_machine") else "pending_manual_review",
        "verified_in_current_env": verified_cats,
        "untested_components": untested_cats,
    },
    "untested_components": untested_cats,
    "evidence_references": [
        "nexus-hw-inventory --json (schema_version=2)",
        "nexus-hw-diagnostics --json (privacy_audit)",
        "docs/HARDWARE_TESTING_GUIDE.md",
        "linux/hardware/hw-compatibility-db.json",
    ],
    "hardware_safety_notice": "Never run destructive disk/installer tests on a primary computer or personal Chromebook.",
    "review_instructions": "Inspect every field below in a text editor before sharing. Community submissions require human maintainer review before entering hw-compatibility-db.json.",
    "system_summary": {
        "architecture": (inv.get("architecture") or {}).get("arch"),
        "is_virtual_machine": env_info.get("is_virtual_machine"),
        "firmware_mode": (inv.get("firmware") or {}).get("mode"),
        "secure_boot": sb.get("secure_boot_state"),
        "shim_signed_present": bool(sb.get("shim_signed_paths")),
        "ram_total_mib": (inv.get("memory") or {}).get("ram_total_mib"),
        "cpu_model": (inv.get("cpu") or {}).get("model"),
        "cpu_category": (inv.get("cpu") or {}).get("category"),
        "gpu_acceleration_mode": gq.get("hardware_acceleration"),
        "gpu_drivers": gq.get("pci_drivers", []),
        "glx_renderer": gq.get("glx_renderer"),
        "vulkan_icds": gq.get("vulkan_icds", []),
    },
    "component_matrix": comp_matrix,
    "browser_gpu_qualification": {
        "firefox": {"status": "NOT TESTED", "webgl": "NOT TESTED", "video_playback": "NOT TESTED"},
        "falkon": {"status": "NOT TESTED", "webgl": "NOT TESTED", "video_playback": "NOT TESTED"},
    },
    "manual_checklist": {
        "wifi_associated": "untested",
        "bluetooth_paired": "untested",
        "speakers_worked": "untested",
        "microphone_worked": "untested",
        "touchpad_gestures_worked": "untested",
        "usb_hotplug_worked": "untested",
        "battery_reporting_accurate": "untested",
        "suspend_resume_worked": "untested",
        "notes": "Fill each field with pass/fail/partial/untested after Stage B manual review; never include serials, SSIDs, or MACs.",
    },
})

md_lines = [
    "# NEXUS OS Safe Hardware Diagnostics Report",
    "",
    f"- **Generated (UTC):** {ts_utc}",
    f"- **Environment:** `{env_info.get('label', 'unknown')}` (VM: `{env_info.get('is_virtual_machine')}`)",
    f"- **Privacy Audit:** `{'PASS' if not leaks else 'FAIL: ' + ','.join(leaks)}` (`auto_upload: false`)",
    f"- **NetworkManager:** `{nm_state}` (Wi-Fi scan capable: `{wifi_scan_capable}`, default route present: `{has_default_route}`)",
    f"- **Graphics Qualification:** `{gq.get('hardware_acceleration', 'unknown')}` (GLX: `{gq.get('glx_renderer') or 'No active X11 GLX session'}`, Vulkan ICDs: `{len(gq.get('vulkan_icds', []))}`)",
    f"- **Secure Boot Chain:** UEFI=`{sb.get('uefi_active')}`, SecureBoot=`{sb.get('secure_boot_state')}`, Shim=`{bool(sb.get('shim_signed_paths'))}`",
    f"- **Audio Sinks:** {len(audio_sinks)} active",
    f"- **Batteries:** {len(report['batteries'])} detected",
    f"- **Suspend Modes Exposed:** {', '.join((report['suspend_capabilities'] or {}).get('mem_sleep') or []) or 'unavailable'} (`tested: false`)",
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
    (out_d / "nexus-hw-contribution-template.json").write_text(json.dumps(contrib_template, indent=2) + "\n", encoding="utf-8")
    export_msg = f"Exported redacted diagnostics to {out_d}/nexus-diagnostics.{{json,md}} and nexus-hw-contribution-template.json"
    print(export_msg, file=sys.stderr if mode in ("json", "contribute") else sys.stdout)

if mode == "json":
    print(json.dumps(report, indent=2))
elif mode == "contribute":
    print(json.dumps(contrib_template, indent=2))
else:
    print(md_text)
PY
