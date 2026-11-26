#!/usr/bin/env bash
# Read-only, privacy-preserving hardware inventory and compatibility classifier.
# Distinguishes verified / partially_verified / supported / detected / untested / unsupported.
# Never outputs serial numbers, MAC addresses, UUIDs, hostnames, or personal usernames.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
DEFAULT_DB="$SCRIPT_DIR/hw-compatibility-db.json"
[[ -r "$DEFAULT_DB" ]] || DEFAULT_DB="/usr/local/share/nexus-os/hardware/hw-compatibility-db.json"

FORMAT="json"
DB_PATH="$DEFAULT_DB"

usage() {
  cat <<'USAGE'
Usage: bash linux/hardware/nexus-hw-inventory.sh [OPTIONS]

Collects a non-destructive, privacy-redacted hardware inventory and classifies
compatibility strictly against hw-compatibility-db.json without claiming real
hardware support merely from Linux detection.

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
    try:
        db = json.loads(db_path.read_text(encoding="utf-8"))
    except Exception:
        db = {}
drv_db = db.get("drivers", {})


def read_text(p: Path):
    try:
        return p.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def classify(category: str, driver: str, fallback: str = "detected") -> dict:
    entry = (drv_db.get(category) or {}).get(driver)
    if entry:
        return {
            "status": entry["status"],
            "scope": entry.get("scope"),
            "test_environment": entry.get("test_environment", "unknown"),
            "required_firmware": entry.get("required_firmware", []),
            "known_issues": entry.get("known_issues"),
            "notes": entry.get("notes"),
        }
    if driver and driver != "none":
        return {
            "status": "detected",
            "scope": "driver_bound_unclassified",
            "test_environment": "untested",
            "required_firmware": [],
            "known_issues": None,
            "notes": f"Kernel driver '{driver}' bound; not yet verified in compatibility DB.",
        }
    return {
        "status": fallback,
        "scope": "no_driver_bound",
        "test_environment": "untested",
        "required_firmware": [],
        "known_issues": "No kernel driver bound to device.",
        "notes": "Device detected without an active kernel driver.",
    }


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

# UEFI, Secure Boot & signed shim presence (no NVRAM/UUID reads)
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

if secure_boot == "unavailable" and shutil.which("mokutil"):
    try:
        mres = subprocess.run(["mokutil", "--sb-state"], capture_output=True, text=True, timeout=3)
        if mres.returncode == 0:
            low = mres.stdout.lower()
            if "enabled" in low:
                secure_boot = "enabled"
            elif "disabled" in low:
                secure_boot = "disabled"
    except Exception:
        pass

shim_paths = []
for efi_cand in ("/boot/efi/EFI/BOOT/BOOTX64.EFI", "/boot/efi/EFI/ubuntu/shimx64.efi", "/boot/efi/EFI/nexus/shimx64.efi", "/usr/lib/shim/shimx64.efi.signed"):
    if Path(efi_cand).is_file():
        shim_paths.append(efi_cand)

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

# PCI GPUs, Network, Audio, and USB Host Controllers
gpus = []
pci_network = []
pci_audio = []
usb_controllers = []
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
    elif cls.startswith("0x0c03"):
        usb_controllers.append({"slot": dev.name, "vendor": vendor, "device": device, "driver": drv, "classification": classify("usb", drv)})

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
        bluetooth.append({"adapter": hci.name, "driver": drv, "classification": classify("bluetooth", drv)})

# Audio cards, ALSA playback/capture, and SOF kernel modules
audio_cards = []
asound = read_text(Path("/proc/asound/cards"))
if asound:
    for line in asound.splitlines():
        if line and line[0].strip().isdigit() and ":" in line:
            audio_cards.append(line.strip())

sof_modules = []
proc_mods = read_text(Path("/proc/modules")) or ""
for line in proc_mods.splitlines():
    mod = line.split(None, 1)[0]
    if "sof" in mod.lower():
        sof_modules.append(mod)

playback_devices = []
if shutil.which("aplay"):
    try:
        ares = subprocess.run(["aplay", "-l"], capture_output=True, text=True, timeout=3)
        if ares.returncode == 0:
            playback_devices = [l.strip() for l in ares.stdout.splitlines() if l.startswith("card ")]
    except Exception:
        pass

capture_devices = []
if shutil.which("arecord"):
    try:
        rres = subprocess.run(["arecord", "-l"], capture_output=True, text=True, timeout=3)
        if rres.returncode == 0:
            capture_devices = [l.strip() for l in rres.stdout.splitlines() if l.startswith("card ")]
    except Exception:
        pass

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
        touchpads.append({"name": name_line, "classification": {"status": "detected", "test_environment": "untested", "notes": "Touchpad input device detected; gestures/palm rejection require physical test."}})

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

# Power management, batteries, and suspend capabilities (STRICTLY READ-ONLY)
batteries = []
ac_adapters = []
ps_dir = Path("/sys/class/power_supply")
if ps_dir.is_dir():
    try:
        ps_nodes = sorted(ps_dir.iterdir())
    except OSError:
        ps_nodes = []
    for node in ps_nodes:
        ptype = read_text(node / "type") or ""
        if node.name.startswith("BAT") or ptype == "Battery":
            batteries.append({
                "name": node.name,
                "status": read_text(node / "status"),
                "capacity_pct": read_text(node / "capacity"),
                "energy_full_uwh": read_text(node / "energy_full"),
                "energy_full_design_uwh": read_text(node / "energy_full_design"),
            })
        elif ptype == "Mains" or node.name.startswith(("AC", "ADP")):
            ac_adapters.append({"name": node.name, "online": read_text(node / "online")})

suspend_states = (read_text(Path("/sys/power/state")) or "").split()
mem_sleep_modes = (read_text(Path("/sys/power/mem_sleep")) or "").split()

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

dmi_vendor = read_text(Path("/sys/devices/virtual/dmi/id/sys_vendor")) or ""
is_qemu = ("qemu" in cpu_model.lower()) or ("qemu" in dmi_vendor.lower()) or any(g["driver"] in ("bochs-drm", "virtio_gpu", "virtio-pci") for g in gpus)
env_label = "qemu_ovmf_tcg" if (is_qemu and uefi_active) else ("qemu_vm" if is_qemu else "bare_metal_or_host")

component_matrix = [
    {
        "category": "gpu",
        "drivers": sorted({g["driver"] for g in gpus}) or ["none"],
        "recognized": len(gpus) > 0,
        "functional_status": "active_drm" if gpus else "none_detected",
        "missing_firmware": [h for h in missing_fw_hints if any(k in h.lower() for k in ("i915", "amdgpu", "radeon", "nvidia", "xe"))],
        "known_limitations": "QEMU virtualized display only does not qualify bare-metal GPUs." if is_qemu else "Physical GPU desktop/Vulkan/hotplug requires manual test.",
        "test_environment": env_label,
        "qualification_status": "verified" if any(g["classification"]["status"] == "tested" for g in gpus) else ("partially_verified" if gpus else "untested"),
    },
    {
        "category": "wifi",
        "drivers": sorted({w["driver"] for w in wifi_adapters}) or ["none"],
        "recognized": len(wifi_adapters) > 0,
        "functional_status": wifi_adapters[0]["operstate"] if wifi_adapters else "not_present",
        "missing_firmware": [h for h in missing_fw_hints if any(k in h.lower() for k in ("iwlwifi", "ath10k", "ath11k", "brcm", "rtw", "mt79"))],
        "known_limitations": "No Wi-Fi hardware attached in QEMU VM; bare-metal WPA2/WPA3 untested." if not wifi_adapters else "Requires physical AP association & suspend recovery test.",
        "test_environment": env_label if wifi_adapters else "none",
        "qualification_status": "untested",
    },
    {
        "category": "bluetooth",
        "drivers": sorted({b["driver"] for b in bluetooth}) or ["none"],
        "recognized": len(bluetooth) > 0,
        "functional_status": "detected" if bluetooth else "not_present",
        "missing_firmware": [h for h in missing_fw_hints if any(k in h.lower() for k in ("bluetooth", "ibt-", "qca"))],
        "known_limitations": "Pairing & A2DP/HFP profiles untested.",
        "test_environment": env_label if bluetooth else "none",
        "qualification_status": "untested",
    },
    {
        "category": "audio_and_sof",
        "drivers": sorted({a["driver"] for a in pci_audio} | set(sof_modules)) or ["none"],
        "recognized": len(audio_cards) > 0 or len(pci_audio) > 0,
        "functional_status": f"{len(playback_devices)}_playback_{len(capture_devices)}_capture" if (playback_devices or capture_devices) else "no_alsa_cards",
        "missing_firmware": [h for h in missing_fw_hints if "sof" in h.lower() or "audio" in h.lower()],
        "known_limitations": "Speakers, internal mics, and Chromebook SOF UCM topologies require physical acoustic testing.",
        "test_environment": env_label if audio_cards else "none",
        "qualification_status": "untested",
    },
    {
        "category": "touchpads_input",
        "drivers": ["libinput"] if touchpads else ["none"],
        "recognized": len(touchpads) > 0,
        "functional_status": f"{len(touchpads)}_touchpad(s)" if touchpads else "none_detected",
        "missing_firmware": [],
        "known_limitations": "Multi-touch gestures and palm rejection require physical touchpad verification.",
        "test_environment": env_label if touchpads else "none",
        "qualification_status": "untested",
    },
    {
        "category": "usb_peripherals",
        "drivers": sorted({u["driver"] for u in usb_controllers}) or ["none"],
        "recognized": len(usb_controllers) > 0 or len(usb_devices) > 0,
        "functional_status": f"{len(usb_devices)}_usb_nodes",
        "missing_firmware": [],
        "known_limitations": "Physical USB-A/USB-C hotplug and DP alt-mode require bare-metal verification.",
        "test_environment": env_label,
        "qualification_status": "partially_verified" if usb_controllers else "untested",
    },
    {
        "category": "power_and_battery",
        "drivers": ["acpi_battery"] if batteries else ["none"],
        "recognized": len(batteries) > 0,
        "functional_status": f"{len(batteries)}_batteries_{len(ac_adapters)}_ac" if (batteries or ac_adapters) else "no_acpi_battery",
        "missing_firmware": [],
        "known_limitations": "Discharge curves and power-profiles require physical laptop battery testing.",
        "test_environment": env_label if batteries else "none",
        "qualification_status": "untested",
    },
    {
        "category": "suspend_resume",
        "drivers": mem_sleep_modes or suspend_states or ["unavailable"],
        "recognized": bool(suspend_states),
        "functional_status": "modes_exposed_not_triggered" if suspend_states else "unavailable",
        "missing_firmware": [],
        "known_limitations": "Suspend/resume is never triggered automatically and remains untested on bare metal.",
        "test_environment": "none",
        "qualification_status": "untested",
    },
    {
        "category": "storage",
        "drivers": sorted({s["driver"] for s in storage}) or ["none"],
        "recognized": len(storage) > 0,
        "functional_status": f"{len(storage)}_disks",
        "missing_firmware": [],
        "known_limitations": "Only QEMU virtio_blk tested; physical NVMe/AHCI/eMMC untested." if is_qemu else "Physical disk install untested.",
        "test_environment": env_label,
        "qualification_status": "partially_verified" if any(s["classification"]["status"] == "tested" for s in storage) else "untested",
    },
    {
        "category": "uefi_and_secure_boot",
        "drivers": ["efifb", "grub-efi-amd64"] + (["shimx64.efi"] if shim_paths else []),
        "recognized": uefi_active,
        "functional_status": f"uefi={uefi_active},secure_boot={secure_boot},shim={bool(shim_paths)}",
        "missing_firmware": [],
        "known_limitations": "Secure Boot enforced mode and OEM NVRAM boot quirks untested on bare metal.",
        "test_environment": env_label,
        "qualification_status": "partially_verified" if uefi_active else "untested",
    },
]

payload = {
    "schema_version": 2,
    "privacy_redacted": True,
    "architecture": {"arch": arch, "status": arch_status},
    "firmware": {
        "mode": "UEFI" if uefi_active else "BIOS/Legacy (or container)",
        "uefi_active": uefi_active,
        "secure_boot": secure_boot,
        "signed_shim_detected": bool(shim_paths),
        "signed_shim_paths": shim_paths,
        "firmware_tree_present": fw_dir_present,
        "missing_firmware_hints": missing_fw_hints[:10],
        "classification": {
            "status": "partially_verified" if uefi_active else "untested",
            "notes": "OVMF UEFI tested in QEMU with Secure Boot off; hardware Secure Boot & BIOS legacy boot untested on bare metal.",
        },
    },
    "cpu": {"model": cpu_model, "logical_cpus": cpu_cores, "status": "detected"},
    "memory": {"ram_total_mib": ram_total_mib, "ram_available_mib": ram_avail_mib},
    "storage": storage,
    "gpus": gpus,
    "displays": displays,
    "network": {"ethernet": ethernet_adapters, "wifi": wifi_adapters, "pci": pci_network},
    "bluetooth": bluetooth,
    "audio": {
        "cards": audio_cards,
        "pci": pci_audio,
        "sof_modules": sof_modules,
        "playback_devices": playback_devices[:8],
        "capture_devices": capture_devices[:8],
    },
    "touchpads": touchpads,
    "usb_controllers": usb_controllers,
    "usb_devices": usb_devices[:25],
    "power_management": {"batteries": batteries, "ac_adapters": ac_adapters},
    "suspend_capabilities": {"states": suspend_states, "mem_sleep": mem_sleep_modes, "tested": False},
    "component_matrix": component_matrix,
}

if fmt == "markdown":
    lines = [
        "# NEXUS OS Hardware Inventory & Compatibility Report",
        "",
        f"- **Architecture:** {arch} (`{arch_status}`)",
        f"- **Firmware:** {payload['firmware']['mode']} (Secure Boot: `{secure_boot}`, Shim: `{bool(shim_paths)}`)",
        f"- **CPU:** {cpu_model} ({cpu_cores} logical CPUs)",
        f"- **RAM:** {ram_total_mib} MiB total / {ram_avail_mib} MiB available",
        f"- **Storage ({len(storage)}):** " + (", ".join(f"{d['device']} ({d['size']}, {d['driver']}: {d['classification']['status']})" for d in storage) or "none detected"),
        f"- **GPUs ({len(gpus)}):** " + (", ".join(f"{g['vendor']}:{g['device']} ({g['driver']}: {g['classification']['status']})" for g in gpus) or "none detected"),
        f"- **Ethernet ({len(ethernet_adapters)}):** " + (", ".join(f"{n['interface']} ({n['driver']}: {n['classification']['status']})" for n in ethernet_adapters) or "none"),
        f"- **Wi-Fi ({len(wifi_adapters)}):** " + (", ".join(f"{w['interface']} ({w['driver']}: {w['classification']['status']})" for w in wifi_adapters) or "none"),
        f"- **Bluetooth ({len(bluetooth)}):** " + (", ".join(b['adapter'] for b in bluetooth) or "none"),
        f"- **Audio Cards ({len(audio_cards)}):** " + ("; ".join(audio_cards) or "none") + (f" (SOF: {','.join(sof_modules)})" if sof_modules else ""),
        f"- **Touchpads ({len(touchpads)}):** " + (", ".join(t['name'] for t in touchpads) or "none"),
        f"- **Batteries ({len(batteries)}):** " + (", ".join(f"{b['name']} ({b['capacity_pct']}%)" for b in batteries) or "none"),
        f"- **Suspend Modes Exposed:** " + (", ".join(mem_sleep_modes or suspend_states) or "unavailable") + " (`tested: false`)",
        f"- **Missing Firmware Hints:** {len(missing_fw_hints)}",
        "",
        "## Component Qualification Matrix",
        "",
        "| Category | Drivers | Recognized | Functional Status | Test Environment | Qualification |",
        "|---|---|---|---|---|---|",
    ]
    for c in component_matrix:
        lines.append(f"| `{c['category']}` | `{','.join(c['drivers'])}` | `{c['recognized']}` | `{c['functional_status']}` | `{c['test_environment']}` | **{c['qualification_status']}** |")
    lines += [
        "",
        "_Privacy notice: Serial numbers, MAC addresses, UUIDs, hostnames, and user identities are omitted._",
    ]
    print("\n".join(lines))
else:
    print(json.dumps(payload, indent=2))
PY
