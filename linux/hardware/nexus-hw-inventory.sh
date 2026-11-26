#!/usr/bin/env bash
# Read-only, privacy-preserving hardware inventory and compatibility classifier.
# Distinguishes Detected / Supported / Tested / Partially tested / Unknown / Unsupported.
# Never outputs serial numbers, MAC addresses, UUIDs, or personal usernames.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
DEFAULT_DB="$SCRIPT_DIR/hw-compatibility-db.json"
[[ -r "$DEFAULT_DB" ]] || DEFAULT_DB="/usr/local/share/nexus-os/hardware/hw-compatibility-db.json"

FORMAT="json"
DB_PATH="$DEFAULT_DB"

usage() {
  cat <<'USAGE'
Usage: bash linux/hardware/nexus-hw-inventory.sh [OPTIONS]

Collects a non-destructive hardware inventory and classifies compatibility
strictly against hw-compatibility-db.json without claiming real hardware
support merely from Linux detection.

Options:
  --json       Output structured JSON inventory (default)
  --markdown   Output Markdown compatibility report
  --db PATH    Override compatibility database JSON path
  --help, -h   Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --json) FORMAT="json"; shift ;;
    --markdown) FORMAT="markdown"; shift ;;
    --db) [[ $# -ge 2 ]] || { echo '--db requires a path' >&2; exit 2; }; DB_PATH="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$FORMAT" "$DB_PATH" <<'PY'
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

fmt = sys.argv[1]
db_path = Path(sys.argv[2])
db = {}
if db_path.is_file():
    db = json.loads(db_path.read_text(encoding="utf-8"))
drv_db = db.get("drivers", {})


def read_text(p: Path):
    try:
        return p.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def classify(category: str, driver: str, fallback: str = "detected") -> dict:
    entry = (drv_db.get(category) or {}).get(driver)
    if entry:
        return {"status": entry["status"], "scope": entry.get("scope"), "notes": entry.get("notes")}
    if driver and driver != "none":
        return {"status": "detected", "scope": "driver_bound_unclassified", "notes": f"Kernel driver '{driver}' bound; not yet verified in compatibility DB."}
    return {"status": fallback, "scope": "no_driver_bound", "notes": "Device detected without an active kernel driver."}


arch = platform.machine()
arch_status = "supported" if arch == "x86_64" else "unsupported"

cpu_model = "unavailable"
cpuinfo = read_text(Path("/proc/cpuinfo"))
if cpuinfo:
    for line in cpuinfo.splitlines():
        if line.lower().startswith("model name"):
            cpu_model = line.split(":", 1)[1].strip()
            break
cpu_cores = os.cpu_count() or 0

ram_total_mib = None
ram_avail_mib = None
meminfo = read_text(Path("/proc/meminfo"))
if meminfo:
    for line in meminfo.splitlines():
        if line.startswith("MemTotal:"):
            tok = line.split(":", 1)[1].strip().split()[0]
            if tok.isdigit():
                ram_total_mib = round(int(tok) / 1024)
        elif line.startswith("MemAvailable:"):
            tok = line.split(":", 1)[1].strip().split()[0]
            if tok.isdigit():
                ram_avail_mib = round(int(tok) / 1024)

# UEFI & Secure Boot (no NVRAM/UUID reads)
uefi_active = Path("/sys/firmware/efi").is_dir()
secure_boot = "unavailable"
try:
    efivars = sorted(Path("/sys/firmware/efi/efivars").glob("SecureBoot-*")) if Path("/sys/firmware/efi/efivars").is_dir() else []
except OSError:
    efivars = []
for cand in efivars:
    try:
        data = cand.read_bytes()
        if len(data) >= 5:
            secure_boot = "enabled" if data[4] == 1 else "disabled"
            break
    except OSError:
        pass

# Storage (explicitly excludes serials/UUIDs/WWNs)
storage = []
if shutil.which("lsblk"):
    try:
        res = subprocess.run(["lsblk", "-J", "-d", "-o", "NAME,SIZE,TYPE,TRAN,RO,RM,MODEL"], capture_output=True, text=True, timeout=4)
        if res.returncode == 0 and res.stdout.strip():
            for dev in json.loads(res.stdout).get("blockdevices", []):
                if dev.get("type") != "disk":
                    continue
                name = dev.get("name", "")
                drv_link = Path(f"/sys/block/{name}/device/driver")
                drv = drv_link.resolve().name if drv_link.is_symlink() else ("virtio_blk" if name.startswith("vd") else "unknown")
                storage.append({
                    "device": f"/dev/{name}",
                    "size": dev.get("size"),
                    "transport": dev.get("tran") or ("virtio" if name.startswith("vd") else "unknown"),
                    "model": (dev.get("model") or "").strip() or "Generic Disk",
                    "driver": drv,
                    "classification": classify("storage", drv, "unknown"),
                })
    except Exception:
        pass

# PCI GPUs & Audio & Wi-Fi/Ethernet
gpus = []
pci_network = []
pci_audio = []
try:
    pci_devs = sorted(Path("/sys/bus/pci/devices").glob("*")) if Path("/sys/bus/pci/devices").is_dir() else []
except OSError:
    pci_devs = []
for dev in pci_devs:
    cls = read_text(dev / "class") or ""
    drv_link = dev / "driver"
    drv = drv_link.resolve().name if drv_link.is_symlink() else "none"
    vendor = read_text(dev / "vendor") or "unknown"
    device = read_text(dev / "device") or "unknown"
    if cls.startswith("0x03"):
        gpus.append({"slot": dev.name, "vendor": vendor, "device": device, "driver": drv, "classification": classify("gpu", drv)})
    elif cls.startswith("0x02"):
        pci_network.append({"slot": dev.name, "class": cls, "vendor": vendor, "device": device, "driver": drv, "classification": classify("network", drv)})
    elif cls.startswith("0x0403") or cls.startswith("0x0401"):
        pci_audio.append({"slot": dev.name, "class": cls, "vendor": vendor, "device": device, "driver": drv, "classification": classify("audio", drv)})

# Network interfaces (explicitly omits MAC addresses & IP addresses)
wifi_adapters = []
ethernet_adapters = []
try:
    net_ifaces = sorted(Path("/sys/class/net").iterdir()) if Path("/sys/class/net").is_dir() else []
except OSError:
    net_ifaces = []
for iface in net_ifaces:
    if iface.name == "lo":
        continue
    drv_link = iface / "device" / "driver"
    drv = drv_link.resolve().name if drv_link.is_symlink() else "none"
    state = read_text(iface / "operstate") or "unknown"
    is_wifi = (iface / "wireless").is_dir() or (iface / "phy80211").is_dir()
    rec = {"interface": iface.name, "operstate": state, "driver": drv, "classification": classify("network", drv)}
    if is_wifi:
        wifi_adapters.append(rec)
    else:
        ethernet_adapters.append(rec)

# Bluetooth
bluetooth = []
bt_dir = Path("/sys/class/bluetooth")
if bt_dir.is_dir():
    try:
        bt_devs = sorted(bt_dir.iterdir())
    except OSError:
        bt_devs = []
    for hci in bt_devs:
        drv_link = hci / "device" / "driver"
        drv = drv_link.resolve().name if drv_link.is_symlink() else "btusb"
        bluetooth.append({"adapter": hci.name, "driver": drv, "classification": {"status": "detected", "notes": "Bluetooth controller detected; pairing/audio untested in CI."}})

# Audio cards
audio_cards = []
asound = read_text(Path("/proc/asound/cards"))
if asound:
    for line in asound.splitlines():
        if line and line[0].strip().isdigit() and ":" in line:
            audio_cards.append(line.strip())

# Displays
displays = []
drm_dir = Path("/sys/class/drm")
if drm_dir.is_dir():
    try:
        drm_conns = sorted(drm_dir.glob("card*-*"))
    except OSError:
        drm_conns = []
    for conn in drm_conns:
        st = read_text(conn / "status") or "unknown"
        modes = (read_text(conn / "modes") or "").splitlines()[:3]
        displays.append({"connector": conn.name, "status": st, "modes": modes})

# Touchpads & Input (no serials)
touchpads = []
inp_text = read_text(Path("/proc/bus/input/devices")) or ""
for block in inp_text.split("\n\n"):
    low = block.lower()
    if any(k in low for k in ("touchpad", "trackpad", "elan", "synaptics")):
        name_line = next((l[3:].strip().strip('"') for l in block.splitlines() if l.startswith("N: Name=")), "Touchpad")
        touchpads.append({"name": name_line, "classification": {"status": "detected", "notes": "Touchpad input device detected; gestures/palm rejection require physical test."}})

# USB devices (vendor:product & class only; NO serials)
usb_devices = []
usb_dir = Path("/sys/bus/usb/devices")
if usb_dir.is_dir():
    try:
        usb_nodes = sorted(usb_dir.iterdir())
    except OSError:
        usb_nodes = []
    for u in usb_nodes:
        vid = read_text(u / "idVendor")
        pid = read_text(u / "idProduct")
        if not (vid and pid):
            continue
        usb_devices.append({
            "id": f"{vid}:{pid}",
            "product": read_text(u / "product") or "USB Device",
            "class": read_text(u / "bDeviceClass") or "00",
        })

# Firmware directory & kernel module visibility
fw_dir_present = Path("/lib/firmware").is_dir() or Path("/usr/lib/firmware").is_dir()
missing_fw_hints = []
if shutil.which("dmesg"):
    try:
        dres = subprocess.run(["dmesg"], capture_output=True, text=True, timeout=3)
        if dres.returncode == 0:
            for line in dres.stdout.splitlines():
                if "direct firmware load" in line.lower() or "failed to load" in line.lower():
                    missing_fw_hints.append(line[:180])
    except Exception:
        pass

payload = {
    "schema_version": 1,
    "privacy_redacted": True,
    "architecture": {"arch": arch, "status": arch_status},
    "firmware": {
        "mode": "UEFI" if uefi_active else "BIOS/Legacy (or container)",
        "uefi_active": uefi_active,
        "secure_boot": secure_boot,
        "firmware_tree_present": fw_dir_present,
        "missing_firmware_hints": missing_fw_hints[:10],
        "classification": {"status": "tested" if uefi_active else "partially_tested", "notes": "OVMF UEFI tested in QEMU; hardware Secure Boot & BIOS legacy boot untested on bare metal."},
    },
    "cpu": {"model": cpu_model, "logical_cpus": cpu_cores, "status": "detected"},
    "memory": {"ram_total_mib": ram_total_mib, "ram_available_mib": ram_avail_mib},
    "storage": storage,
    "gpus": gpus,
    "displays": displays,
    "network": {"ethernet": ethernet_adapters, "wifi": wifi_adapters, "pci": pci_network},
    "bluetooth": bluetooth,
    "audio": {"cards": audio_cards, "pci": pci_audio},
    "touchpads": touchpads,
    "usb_devices": usb_devices[:25],
}

if fmt == "markdown":
    lines = [
        "# NEXUS OS Hardware Inventory & Compatibility Report",
        "",
        f"- **Architecture:** {arch} (`{arch_status}`)",
        f"- **Firmware:** {payload['firmware']['mode']} (Secure Boot: `{secure_boot}`)",
        f"- **CPU:** {cpu_model} ({cpu_cores} logical CPUs)",
        f"- **RAM:** {ram_total_mib} MiB total / {ram_avail_mib} MiB available",
        f"- **Storage ({len(storage)}):** " + (", ".join(f"{d['device']} ({d['size']}, {d['driver']}: {d['classification']['status']})" for d in storage) or "none detected"),
        f"- **GPUs ({len(gpus)}):** " + (", ".join(f"{g['vendor']}:{g['device']} ({g['driver']}: {g['classification']['status']})" for g in gpus) or "none detected"),
        f"- **Ethernet ({len(ethernet_adapters)}):** " + (", ".join(f"{n['interface']} ({n['driver']}: {n['classification']['status']})" for n in ethernet_adapters) or "none"),
        f"- **Wi-Fi ({len(wifi_adapters)}):** " + (", ".join(f"{w['interface']} ({w['driver']}: {w['classification']['status']})" for w in wifi_adapters) or "none"),
        f"- **Bluetooth ({len(bluetooth)}):** " + (", ".join(b['adapter'] for b in bluetooth) or "none"),
        f"- **Audio Cards ({len(audio_cards)}):** " + ("; ".join(audio_cards) or "none"),
        f"- **Touchpads ({len(touchpads)}):** " + (", ".join(t['name'] for t in touchpads) or "none"),
        f"- **Missing Firmware Hints:** {len(missing_fw_hints)}",
        "",
        "_Privacy notice: Serial numbers, MAC addresses, UUIDs, and user identities are omitted._",
    ]
    print("\n".join(lines))
else:
    print(json.dumps(payload, indent=2))
PY
