#!/usr/bin/env bash
# Read-only, privacy-preserving hardware inventory and compatibility classifier.
# Distinguishes verified / partially_verified / supported / detected / untested / unsupported.
# Strictly distinguishes genuine hardware GPU acceleration from QEMU / VirtIO / Bochs / llvmpipe.
# Never outputs serial numbers, MAC addresses, UUIDs, hostnames, SSIDs, or personal usernames.
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
import re
import shutil
import socket
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
ACTIVE_HOST = socket.gethostname()
ACTIVE_USER = os.environ.get("USER", "")


def read_text(p: Path):
    try:
        return p.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def redact_line(text: str) -> str:
    text = re.sub(r"\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", "<REDACTED_MAC>", text)
    text = re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "<REDACTED_UUID>", text)
    text = re.sub(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "<REDACTED_IP>", text)
    text = re.sub(r"\bfe80:[0-9a-fA-F:]+\b", "<REDACTED_IPV6>", text)
    text = re.sub(r"/home/[A-Za-z0-9._-]+", "/home/<USER>", text)
    if ACTIVE_HOST and len(ACTIVE_HOST) > 2:
        text = re.sub(rf"\b{re.escape(ACTIVE_HOST)}\b", "<REDACTED_HOST>", text)
    if ACTIVE_USER and len(ACTIVE_USER) > 2 and ACTIVE_USER not in ("root", "user", "nexus"):
        text = re.sub(rf"\b{re.escape(ACTIVE_USER)}\b", "<USER>", text)
    return text


def redact_obj(obj):
    if isinstance(obj, str):
        return redact_line(obj)
    if isinstance(obj, list):
        return [redact_obj(x) for x in obj]
    if isinstance(obj, dict):
        return {k: redact_obj(v) for k, v in obj.items()}
    return obj


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
cpu_flags = []
cpuinfo = read_text(Path("/proc/cpuinfo"))
if cpuinfo:
    for line in cpuinfo.splitlines():
        low = line.lower()
        if low.startswith("model name") and cpu_model == "unavailable":
            cpu_model = line.split(":", 1)[1].strip()
        elif low.startswith("flags") and not cpu_flags:
            cpu_flags = line.split(":", 1)[1].strip().split()
cpu_cores = os.cpu_count() or 0
cpu_low = cpu_model.lower()
if "qemu" in cpu_low or "virtual" in cpu_low or "hypervisor" in cpu_flags:
    cpu_category = "virtual_or_emulated"
elif "intel" in cpu_low:
    cpu_category = "intel_x86_64"
elif "amd" in cpu_low or "ryzen" in cpu_low or "epyc" in cpu_low:
    cpu_category = "amd_x86_64"
else:
    cpu_category = "other_x86_64" if arch == "x86_64" else "non_x86_64"
hw_virt = "vmx" if "vmx" in cpu_flags else ("svm" if "svm" in cpu_flags else "none")

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

# UEFI, Secure Boot & signed boot chain (no NVRAM UUID reads)
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

shim_paths = [
    p for p in (
        "/boot/efi/EFI/BOOT/BOOTX64.EFI",
        "/boot/efi/EFI/ubuntu/shimx64.efi",
        "/boot/efi/EFI/nexus/shimx64.efi",
        "/usr/lib/shim/shimx64.efi.signed",
    ) if Path(p).is_file()
]
grub_signed_paths = [
    p for p in (
        "/boot/efi/EFI/ubuntu/grubx64.efi",
        "/boot/efi/EFI/nexus/grubx64.efi",
        "/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed",
    ) if Path(p).is_file()
]
kernel_images = sorted(str(p) for p in Path("/boot").glob("vmlinuz-*")) if Path("/boot").is_dir() else []

sb_packages = {}
if shutil.which("dpkg-query"):
    for pkg in ("shim-signed", "grub-efi-amd64-signed", "mokutil"):
        try:
            qres = subprocess.run(["dpkg-query", "-W", "-f=${Status}", pkg], capture_output=True, text=True, timeout=2)
            sb_packages[pkg] = (qres.returncode == 0 and "install ok installed" in qres.stdout)
        except Exception:
            sb_packages[pkg] = False

def check_pe_sig(paths):
    if not shutil.which("sbverify"):
        return "sbverify_unavailable"
    existing = [p for p in paths if Path(p).is_file()]
    if not existing:
        return "binary_not_present"
    for p in existing:
        try:
            sres = subprocess.run(["sbverify", "--list", p], capture_output=True, text=True, timeout=3)
            low = (sres.stdout or "").lower()
            if sres.returncode == 0 and ("signature 1" in low or "subject:" in low or "subject=" in low):
                return "signed_pe_present"
        except Exception:
            return "check_error"
    return "unsigned_or_unverified"


kernel_sb_verified = check_pe_sig(kernel_images)
shim_sb_verified = check_pe_sig(shim_paths)
grub_sb_verified = check_pe_sig(grub_signed_paths)

# Storage (explicitly excludes serials/UUIDs/WWNs)
storage = []
if shutil.which("lsblk"):
    try:
        res = subprocess.run(["lsblk", "-J", "-d", "-o", "NAME,SIZE,TYPE,TRAN,RO,RM,ROTA,MODEL"], capture_output=True, text=True, timeout=4)
        if res.returncode == 0 and res.stdout.strip():
            for dev in json.loads(res.stdout).get("blockdevices", []):
                if dev.get("type") != "disk":
                    continue
                name = dev.get("name", "")
                drv_link = Path(f"/sys/block/{name}/device/driver")
                drv = drv_link.resolve().name if drv_link.is_symlink() else ("virtio_blk" if name.startswith("vd") else "unknown")
                tran = dev.get("tran") or ("virtio" if name.startswith("vd") else "unknown")
                rota = dev.get("rota")
                if name.startswith("nvme"):
                    drive_type = "nvme_ssd"
                elif name.startswith("mmcblk"):
                    drive_type = "emmc_or_sd"
                elif name.startswith("vd") or tran == "virtio":
                    drive_type = "virtio_virtual_disk"
                elif tran == "usb":
                    drive_type = "usb_disk"
                elif rota in (False, 0, "0"):
                    drive_type = "sata_ssd"
                elif rota in (True, 1, "1"):
                    drive_type = "sata_hdd"
                else:
                    drive_type = "unknown_disk"
                storage.append({
                    "device": f"/dev/{name}",
                    "size": dev.get("size"),
                    "transport": tran,
                    "drive_type": drive_type,
                    "model": (dev.get("model") or "").strip() or "Generic Disk",
                    "driver": drv,
                    "classification": classify("storage", drv, "unknown"),
                })
    except Exception:
        pass

# PCI GPUs, Network, Audio, Storage, and USB Host Controllers
PCI_VENDORS = {
    "0x8086": "Intel",
    "0x1002": "AMD/ATI",
    "0x10de": "NVIDIA",
    "0x1234": "QEMU/Bochs",
    "0x1af4": "Red Hat/VirtIO",
    "0x10ec": "Realtek",
    "0x14e4": "Broadcom",
    "0x17cb": "Qualcomm",
    "0x14c3": "MediaTek",
    "0x15b3": "Mellanox",
    "0x1b21": "ASMedia",
    "0x144d": "Samsung",
    "0x2646": "Kingston",
    "0x15b7": "SanDisk/WD",
    "0xc0a9": "Micron/Crucial",
}
gpus = []
pci_network = []
pci_audio = []
storage_controllers = []
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
    vendor_name = PCI_VENDORS.get(vendor.lower(), vendor)
    device = read_text(dev / "device") or "unknown"
    if cls.startswith("0x03"):
        gpus.append({"slot": dev.name, "vendor": vendor, "vendor_name": vendor_name, "device": device, "driver": drv, "classification": classify("gpu", drv)})
    elif cls.startswith("0x02"):
        pci_network.append({"slot": dev.name, "class": cls, "vendor": vendor, "vendor_name": vendor_name, "device": device, "driver": drv, "classification": classify("network", drv)})
    elif cls.startswith("0x0403") or cls.startswith("0x0401"):
        pci_audio.append({"slot": dev.name, "class": cls, "vendor": vendor, "vendor_name": vendor_name, "device": device, "driver": drv, "classification": classify("audio", drv)})
    elif cls.startswith("0x01"):
        ctrl_kind = "nvme" if cls.startswith("0x0108") else ("sata_ahci" if cls.startswith("0x0106") else ("raid" if cls.startswith("0x0104") else "scsi_or_other"))
        storage_controllers.append({"slot": dev.name, "class": cls, "controller_type": ctrl_kind, "vendor": vendor, "vendor_name": vendor_name, "device": device, "driver": drv, "classification": classify("storage", drv, "detected")})
    elif cls.startswith("0x0c03"):
        usb_controllers.append({"slot": dev.name, "vendor": vendor, "vendor_name": vendor_name, "device": device, "driver": drv, "classification": classify("usb", drv)})

# Network interfaces (explicitly omits MAC addresses, IP addresses, and SSIDs)
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

nm_state = "unavailable"
wifi_radio = "unavailable"
wifi_hw = "unavailable"
if shutil.which("nmcli"):
    try:
        nm_state = subprocess.run(["nmcli", "-t", "-f", "STATE", "general"], capture_output=True, text=True, timeout=3).stdout.strip() or "unknown"
        wres = subprocess.run(["nmcli", "-t", "-f", "WIFI,WIFI-HW", "general"], capture_output=True, text=True, timeout=3)
        if wres.returncode == 0 and ":" in wres.stdout:
            parts = wres.stdout.strip().split(":", 1)
            wifi_radio = parts[0]
            wifi_hw = parts[1]
    except Exception:
        pass

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

# Audio cards, codecs, ALSA playback/capture, PipeWire/PulseAudio, and SOF status (NO recording)
audio_cards = []
asound = read_text(Path("/proc/asound/cards"))
if asound:
    for line in asound.splitlines():
        if line and line[0].strip().isdigit() and ":" in line:
            audio_cards.append(line.strip())

audio_codecs = []
asound_dir = Path("/proc/asound")
if asound_dir.is_dir():
    try:
        for cf in sorted(asound_dir.glob("card*/codec#*")):
            txt = read_text(cf) or ""
            for line in txt.splitlines():
                if line.startswith("Codec:"):
                    audio_codecs.append(line.split(":", 1)[1].strip())
                    break
    except OSError:
        pass

sof_modules = []
proc_mods = read_text(Path("/proc/modules")) or ""
for line in proc_mods.splitlines():
    mod = line.split(None, 1)[0]
    if "sof" in mod.lower():
        sof_modules.append(mod)

sof_fw_count = 0
for sof_dir in (Path("/lib/firmware/intel/sof"), Path("/usr/lib/firmware/intel/sof")):
    if sof_dir.is_dir():
        try:
            sof_fw_count += sum(1 for _ in sof_dir.rglob("*"))
        except OSError:
            pass

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

audio_server = "unavailable"
audio_service_errors = []
if shutil.which("pactl"):
    try:
        ires = subprocess.run(["pactl", "info"], capture_output=True, text=True, timeout=3)
        if ires.returncode == 0:
            for line in ires.stdout.splitlines():
                if line.startswith("Server Name:"):
                    audio_server = line.split(":", 1)[1].strip()
                    break
        elif ires.stderr.strip():
            audio_service_errors.append(redact_line(ires.stderr.strip().splitlines()[0][:160]))
    except Exception:
        pass
elif shutil.which("wpctl"):
    audio_server = "pipewire_wpctl_present"

if shutil.which("journalctl"):
    try:
        jres = subprocess.run(
            ["journalctl", "--user", "-u", "pipewire", "-u", "wireplumber", "-u", "pipewire-pulse", "-p", "err", "-n", "5", "--no-pager", "-q"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if jres.returncode == 0 and jres.stdout.strip():
            audio_service_errors.extend(redact_line(l[:160]) for l in jres.stdout.splitlines()[:5] if l.strip())
    except Exception:
        pass

# Displays, DRI nodes, Mesa, GLX & Vulkan (read-only)
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

dri_nodes = sorted(str(p) for p in Path("/dev/dri").glob("*")) if Path("/dev/dri").is_dir() else []
mesa_dri_present = Path("/usr/lib/x86_64-linux-gnu/dri").is_dir()
vulkan_icds = sorted(p.name for p in Path("/usr/share/vulkan/icd.d").glob("*.json")) if Path("/usr/share/vulkan/icd.d").is_dir() else []

glx_vendor = None
glx_renderer = None
glx_direct = None
if shutil.which("glxinfo"):
    try:
        gres = subprocess.run(["glxinfo", "-B"], capture_output=True, text=True, timeout=4)
        if gres.returncode == 0:
            for line in gres.stdout.splitlines():
                s = line.strip()
                if s.startswith("OpenGL vendor string:"):
                    glx_vendor = s.split(":", 1)[1].strip()
                elif s.startswith("OpenGL renderer string:"):
                    glx_renderer = s.split(":", 1)[1].strip()
                elif s.startswith("direct rendering:"):
                    glx_direct = s.split(":", 1)[1].strip()
    except Exception:
        pass

vulkan_summary = []
if shutil.which("vulkaninfo"):
    try:
        vres = subprocess.run(["vulkaninfo", "--summary"], capture_output=True, text=True, timeout=4)
        if vres.returncode == 0:
            vulkan_summary = [redact_line(l.strip()) for l in vres.stdout.splitlines() if "deviceName" in l or "driverName" in l][:6]
    except Exception:
        pass

# Touchpads & Input devices (explicitly excludes Uniq serials/MACs)
touchpads = []
input_devices = []
inp_text = read_text(Path("/proc/bus/input/devices")) or ""
for block in inp_text.split("\n\n"):
    if not block.strip():
        continue
    low = block.lower()
    name_line = next((l[3:].strip().strip('"') for l in block.splitlines() if l.startswith("N: Name=")), "")
    handlers_line = next((l[3:].strip() for l in block.splitlines() if l.startswith("H: Handlers=")), "")
    if not name_line:
        continue
    is_tp = any(k in low for k in ("touchpad", "trackpad", "elan", "synaptics"))
    if is_tp:
        cat = "touchpad"
        touchpads.append({"name": name_line, "classification": {"status": "detected", "test_environment": "untested", "notes": "Touchpad input device detected; gestures/palm rejection require physical test."}})
    elif "kbd" in handlers_line or "keyboard" in low:
        cat = "keyboard"
    elif "mouse" in handlers_line or "pointer" in low or "tablet" in low:
        cat = "pointer_or_mouse"
    elif "touchscreen" in low:
        cat = "touchscreen"
    else:
        cat = "other_input"
    input_devices.append({"name": name_line, "category": cat})

# USB devices (vendor:product, class, and peripheral category only; NO serials)
USB_CLASS_MAP = {
    "01": "audio",
    "02": "communications_network",
    "03": "hid_input",
    "06": "imaging",
    "07": "printer",
    "08": "mass_storage",
    "09": "usb_hub",
    "0a": "cdc_data",
    "0b": "smart_card",
    "0e": "video_webcam",
    "e0": "wireless_bluetooth",
    "ef": "composite_misc",
    "fe": "app_specific",
    "ff": "vendor_specific",
}
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
        bcls = (read_text(u / "bDeviceClass") or "00").lower()
        iface_classes = []
        if bcls in ("00", "ef"):
            try:
                for icf in sorted(u.glob(f"{u.name}:*/bInterfaceClass")):
                    ic = (read_text(icf) or "").lower()
                    if ic:
                        iface_classes.append(ic)
            except OSError:
                pass
        eff_cls = iface_classes[0] if iface_classes else bcls
        usb_cat = USB_CLASS_MAP.get(eff_cls, "other_usb")
        usb_devices.append({
            "id": f"{vid}:{pid}",
            "product": read_text(u / "product") or "USB Device",
            "class": bcls,
            "interface_classes": iface_classes[:4],
            "category": usb_cat,
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
scaling_governor = read_text(Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")) or "unavailable"
upower_active = False
ppd_active = False
if shutil.which("systemctl"):
    try:
        upower_active = subprocess.run(["systemctl", "is-active", "--quiet", "upower"], capture_output=True, timeout=2).returncode == 0
        ppd_active = subprocess.run(["systemctl", "is-active", "--quiet", "power-profiles-daemon"], capture_output=True, timeout=2).returncode == 0
    except Exception:
        pass

# Firmware directory & kernel module / driver error visibility
fw_dir_present = Path("/lib/firmware").is_dir() or Path("/usr/lib/firmware").is_dir()
missing_fw_hints = []
gpu_driver_errors = []
audio_driver_errors = []
if shutil.which("dmesg"):
    try:
        dres = subprocess.run(["dmesg"], capture_output=True, text=True, timeout=3)
        if dres.returncode == 0:
            for line in dres.stdout.splitlines():
                low = line.lower()
                if "direct firmware load" in low or "failed to load" in low:
                    missing_fw_hints.append(redact_line(line[:180]))
                if ("error" in low or "fail" in low or "fault" in low) and any(k in low for k in ("drm", "i915", "xe ", "amdgpu", "radeon", "nouveau", "nvidia")):
                    gpu_driver_errors.append(redact_line(line[:180]))
                if ("error" in low or "fail" in low) and any(k in low for k in ("sof", "snd_hda", "alsa", "audio")):
                    audio_driver_errors.append(redact_line(line[:180]))
    except Exception:
        pass

dmi_vendor = read_text(Path("/sys/devices/virtual/dmi/id/sys_vendor")) or ""
dmi_family = read_text(Path("/sys/devices/virtual/dmi/id/product_family")) or ""
dmi_product = read_text(Path("/sys/devices/virtual/dmi/id/product_name")) or ""
is_qemu = ("qemu" in cpu_low) or ("qemu" in dmi_vendor.lower()) or any(g["driver"] in ("bochs-drm", "virtio_gpu", "virtio-pci") for g in gpus)
is_vm = is_qemu or (cpu_category == "virtual_or_emulated") or any(k in dmi_vendor.lower() for k in ("virtualbox", "vmware", "microsoft corporation", "xen", "innotek"))
is_chromebook = any(k in (dmi_family + " " + dmi_product + " " + dmi_vendor).lower() for k in ("chromebook", "chromebox", "google", "coreboot")) and not is_vm
env_label = "qemu_ovmf_tcg" if (is_qemu and uefi_active) else ("virtual_machine" if is_vm else "bare_metal_or_host")

gpu_drivers = sorted({g["driver"] for g in gpus})
software_render = (
    is_vm
    or any(d in ("bochs-drm", "virtio_gpu", "virtio-pci", "none") for d in gpu_drivers)
    or (glx_renderer is not None and any(k in glx_renderer.lower() for k in ("llvmpipe", "softpipe", "swrast")))
)
if not gpus:
    gpu_accel_mode = "unavailable"
elif software_render:
    gpu_accel_mode = "software_llvmpipe_or_virtual"
elif any(d in ("i915", "xe", "amdgpu", "nvidia") for d in gpu_drivers):
    gpu_accel_mode = "genuine_hardware_gpu_driver_bound"
else:
    gpu_accel_mode = "unclassified_gpu_driver"

component_matrix = [
    {
        "category": "gpu",
        "drivers": gpu_drivers or ["none"],
        "recognized": len(gpus) > 0,
        "functional_status": gpu_accel_mode,
        "missing_firmware": [h for h in missing_fw_hints if any(k in h.lower() for k in ("i915", "amdgpu", "radeon", "nvidia", "xe"))],
        "known_limitations": "QEMU virtualized/software rendering only; does not qualify physical GPUs." if is_vm else "Physical GPU desktop/Vulkan/WebGL/hotplug requires manual test.",
        "test_environment": env_label,
        "qualification_status": "verified" if any(g["classification"]["status"] == "tested" for g in gpus) else ("partially_verified" if gpus else "untested"),
    },
    {
        "category": "wifi",
        "drivers": sorted({w["driver"] for w in wifi_adapters}) or ["none"],
        "recognized": len(wifi_adapters) > 0,
        "functional_status": wifi_adapters[0]["operstate"] if wifi_adapters else "not_present",
        "missing_firmware": [h for h in missing_fw_hints if any(k in h.lower() for k in ("iwlwifi", "ath10k", "ath11k", "brcm", "rtw", "mt79"))],
        "known_limitations": "No Wi-Fi hardware attached in VM; bare-metal WPA2/WPA3 untested." if not wifi_adapters else "Requires physical AP association & suspend recovery test.",
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
        "known_limitations": "Only QEMU virtio_blk tested; physical NVMe/AHCI/eMMC untested." if is_vm else "Physical disk install untested.",
        "test_environment": env_label,
        "qualification_status": "partially_verified" if any(s["classification"]["status"] == "tested" for s in storage) else "untested",
    },
    {
        "category": "uefi_and_secure_boot",
        "drivers": ["efifb", "grub-efi-amd64"] + (["shimx64.efi"] if shim_paths else []),
        "recognized": uefi_active,
        "functional_status": f"uefi={uefi_active},secure_boot={secure_boot},shim={bool(shim_paths)}",
        "missing_firmware": [],
        "known_limitations": "Secure Boot enforced mode and OEM NVRAM boot quirks require dedicated validation.",
        "test_environment": env_label,
        "qualification_status": "verified" if (uefi_active and secure_boot == "enabled") else ("partially_verified" if uefi_active else "untested"),
    },
]

payload = {
    "schema_version": 2,
    "privacy_redacted": True,
    "environment": {
        "label": env_label,
        "is_virtual_machine": is_vm,
        "is_qemu": is_qemu,
        "is_chromebook_board": is_chromebook,
    },
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
            "status": "verified" if (uefi_active and secure_boot == "enabled") else ("partially_verified" if uefi_active else "untested"),
            "notes": "OVMF UEFI tested in QEMU; Secure Boot enforced only when mokutil/efivar reports enabled.",
        },
    },
    "secure_boot_chain": {
        "uefi_active": uefi_active,
        "secure_boot_state": secure_boot,
        "shim_signed_paths": shim_paths,
        "shim_sb_status": shim_sb_verified,
        "grub_signed_paths": grub_signed_paths,
        "grub_sb_status": grub_sb_verified,
        "kernel_images_count": len(kernel_images),
        "kernel_sb_status": kernel_sb_verified,
        "packages_installed": sb_packages,
    },
    "cpu": {"model": cpu_model, "category": cpu_category, "logical_cpus": cpu_cores, "hw_virt": hw_virt, "status": "detected"},
    "memory": {"ram_total_mib": ram_total_mib, "ram_available_mib": ram_avail_mib},
    "storage_controllers": storage_controllers,
    "storage": storage,
    "gpus": gpus,
    "graphics_qualification": {
        "pci_drivers": gpu_drivers,
        "dri_nodes": dri_nodes,
        "mesa_dri_present": mesa_dri_present,
        "glx_vendor": glx_vendor,
        "glx_renderer": glx_renderer,
        "glx_direct_rendering": glx_direct,
        "vulkan_icds": vulkan_icds,
        "vulkan_summary": vulkan_summary,
        "hardware_acceleration": gpu_accel_mode,
        "software_rendering_fallback": software_render,
        "gpu_firmware_errors": [h for h in missing_fw_hints if any(k in h.lower() for k in ("i915", "amdgpu", "radeon", "nvidia", "xe", "drm"))],
        "gpu_driver_errors": gpu_driver_errors[:10],
    },
    "displays": displays,
    "network": {"ethernet": ethernet_adapters, "wifi": wifi_adapters, "pci": pci_network},
    "network_qualification": {
        "networkmanager_state": nm_state,
        "wifi_adapter_count": len(wifi_adapters),
        "ethernet_adapter_count": len(ethernet_adapters),
        "wifi_hw_enabled": wifi_hw,
        "wifi_radio_enabled": wifi_radio,
        "bluetooth_adapter_count": len(bluetooth),
        "missing_network_firmware": [h for h in missing_fw_hints if any(k in h.lower() for k in ("iwlwifi", "ath", "brcm", "rtw", "mt79", "bt", "ibt-"))],
    },
    "bluetooth": bluetooth,
    "audio": {
        "cards": audio_cards,
        "codecs": audio_codecs,
        "pci": pci_audio,
        "sof_modules": sof_modules,
        "sof_firmware_files_count": sof_fw_count,
        "audio_server": audio_server,
        "playback_devices": playback_devices[:8],
        "capture_devices": capture_devices[:8],
        "audio_firmware_errors": [h for h in missing_fw_hints if any(k in h.lower() for k in ("sof", "snd", "audio", "hda"))],
        "audio_service_errors": (audio_service_errors + audio_driver_errors)[:10],
    },
    "touchpads": touchpads,
    "input_devices": input_devices[:30],
    "usb_controllers": usb_controllers,
    "usb_devices": usb_devices[:25],
    "power_management": {
        "batteries": batteries,
        "ac_adapters": ac_adapters,
        "upower_service_active": upower_active,
        "power_profiles_daemon_active": ppd_active,
        "cpu_scaling_governor": scaling_governor,
    },
    "suspend_capabilities": {"states": suspend_states, "mem_sleep": mem_sleep_modes, "tested": False},
    "component_matrix": component_matrix,
}

payload = redact_obj(payload)

if fmt == "markdown":
    lines = [
        "# NEXUS OS Hardware Inventory & Compatibility Report",
        "",
        f"- **Environment:** `{env_label}` (VM: `{is_vm}`, Chromebook board: `{is_chromebook}`)",
        f"- **Architecture:** {arch} (`{arch_status}`)",
        f"- **Firmware & Secure Boot:** {payload['firmware']['mode']} (Secure Boot: `{secure_boot}`, Shim: `{bool(shim_paths)}` [`{shim_sb_verified}`], GRUB SB: `{grub_sb_verified}`, Kernel SB: `{kernel_sb_verified}`)",
        f"- **CPU:** {cpu_model} (`{cpu_category}`, {cpu_cores} logical CPUs, virt: `{hw_virt}`, governor: `{scaling_governor}`)",
        f"- **RAM:** {ram_total_mib} MiB total / {ram_avail_mib} MiB available",
        f"- **Graphics Qualification:** `{gpu_accel_mode}` (Drivers: `{','.join(gpu_drivers) or 'none'}`, GLX: `{glx_renderer or 'no active X11 GLX'}`, Vulkan ICDs: `{len(vulkan_icds)}`)",
        f"- **Storage ({len(storage)}):** " + (", ".join(f"{d['device']} ({d['size']}, {d['drive_type']}, {d['driver']}: {d['classification']['status']})" for d in storage) or "none detected"),
        f"- **Network:** NM=`{nm_state}`, Ethernet={len(ethernet_adapters)}, Wi-Fi={len(wifi_adapters)} (radio=`{wifi_radio}`), Bluetooth={len(bluetooth)}",
        f"- **Audio:** Server=`{audio_server}`, Cards={len(audio_cards)}, Codecs={len(audio_codecs)}, Playback={len(playback_devices)}, Capture={len(capture_devices)}, SOF files={sof_fw_count}",
        f"- **Touchpads / Input:** {len(touchpads)} touchpad(s), {len(input_devices)} input device(s)",
        f"- **Batteries ({len(batteries)}):** " + (", ".join(f"{b['name']} ({b['capacity_pct']}%)" for b in batteries) or "none") + f" (upower active: `{upower_active}`)",
        f"- **Suspend Modes Exposed:** " + (", ".join(mem_sleep_modes or suspend_states) or "unavailable") + " (`tested: false`)",
        f"- **Missing Firmware Hints:** {len(missing_fw_hints)}",
        "",
        "## Component Qualification Matrix",
        "",
        "| Category | Drivers | Recognized | Functional Status | Test Environment | Qualification |",
        "|---|---|---|---|---|---|",
    ]
    for c in payload["component_matrix"]:
        lines.append(f"| `{c['category']}` | `{','.join(c['drivers'])}` | `{c['recognized']}` | `{c['functional_status']}` | `{c['test_environment']}` | **{c['qualification_status']}** |")
    lines += [
        "",
        "_Privacy notice: Serial numbers, MAC addresses, UUIDs, SSIDs, hostnames, and user identities are omitted._",
    ]
    print("\n".join(lines))
else:
    print(json.dumps(payload, indent=2))
PY
