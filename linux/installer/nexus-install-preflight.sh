#!/usr/bin/env bash
# Read-only hardware, firmware, storage, dual-boot, Secure Boot, and installer readiness probe
# for NEXUS OS (Linux Mint 22.3 / Ubuntu Noble live/installed environments).
# Never alters partitions, disks, or system state.
set -euo pipefail

FORMAT="json"

usage() {
  cat <<'USAGE'
Usage: bash linux/installer/nexus-install-preflight.sh [OPTIONS]

Reports real hardware, firmware (UEFI/BIOS), Secure Boot chain, block storage,
dual-boot/NTFS/ESP partition detection, network, audio, battery, and installer
availability. Read-only.

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


def read_text(path: Path):
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


arch = platform.machine()
uefi_active = Path("/sys/firmware/efi").is_dir()
firmware = "UEFI" if uefi_active else "BIOS/Legacy (or container)"

secure_boot = "unavailable"
if uefi_active:
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

shim_present = any(Path(p).is_file() for p in (
    "/usr/lib/shim/shimx64.efi.signed",
    "/boot/efi/EFI/ubuntu/shimx64.efi",
    "/boot/efi/EFI/nexus/shimx64.efi",
    "/boot/efi/EFI/BOOT/BOOTX64.EFI",
))
grub_efi_signed_present = any(Path(p).is_file() for p in (
    "/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed",
    "/boot/efi/EFI/ubuntu/grubx64.efi",
    "/boot/efi/EFI/nexus/grubx64.efi",
))
grub_pc_available = Path("/usr/lib/grub/i386-pc").is_dir()

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

# Block disks & read-only partition/dual-boot detection via lsblk (never mounts or formats)
disks = []
esp_partitions = []
ntfs_partitions = []
linux_partitions = []
luks_partitions = []

if shutil.which("lsblk"):
    try:
        res = subprocess.run(
            ["lsblk", "-J", "-o", "NAME,SIZE,MODEL,TYPE,FSTYPE,PARTTYPENAME,RO,RM"],
            capture_output=True,
            text=True,
            timeout=4,
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)

            def walk_parts(node):
                for ch in node.get("children", []) or []:
                    ptype = ch.get("type")
                    name = f"/dev/{ch.get('name')}"
                    fstype = (ch.get("fstype") or "").lower()
                    parttype = (ch.get("parttypename") or "").lower()
                    if ptype in ("part", "crypt"):
                        rec = {"device": name, "size": ch.get("size"), "fstype": fstype or "unknown"}
                        if fstype == "vfat" or "efi" in parttype:
                            esp_partitions.append(rec)
                        elif fstype == "ntfs" or "microsoft basic data" in parttype:
                            ntfs_partitions.append(rec)
                        elif fstype in ("ext4", "btrfs", "xfs"):
                            linux_partitions.append(rec)
                        elif fstype == "crypto_luks":
                            luks_partitions.append(rec)
                    walk_parts(ch)

            for dev in data.get("blockdevices", []):
                if dev.get("type") == "disk":
                    disks.append({
                        "device": f"/dev/{dev.get('name')}",
                        "size": dev.get("size"),
                        "model": (dev.get("model") or "").strip() or "Unknown",
                        "removable": bool(dev.get("rm")),
                    })
                walk_parts(dev)
    except Exception:
        pass

gpus = []
try:
    pci_devs = sorted(Path("/sys/bus/pci/devices").glob("*")) if Path("/sys/bus/pci/devices").is_dir() else []
except OSError:
    pci_devs = []
for dev in pci_devs:
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
try:
    net_devs = sorted(Path("/sys/class/net").iterdir()) if Path("/sys/class/net").is_dir() else []
except OSError:
    net_devs = []
for iface in net_devs:
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
try:
    drm_conns = sorted(Path("/sys/class/drm").glob("card*-*")) if Path("/sys/class/drm").is_dir() else []
except OSError:
    drm_conns = []
for conn in drm_conns:
    status = read_text(conn / "status")
    if status == "connected":
        displays.append(conn.name)

battery = None
try:
    bats = sorted(Path("/sys/class/power_supply").glob("BAT*")) if Path("/sys/class/power_supply").is_dir() else []
except OSError:
    bats = []
for bat in bats:
    cap = read_text(bat / "capacity")
    status = read_text(bat / "status")
    battery = {"name": bat.name, "capacity": int(cap) if cap and cap.isdigit() else None, "status": status or "unknown"}
    break

ubiquity_path = shutil.which("ubiquity")
os_prober_path = shutil.which("os-prober")
cryptsetup_path = shutil.which("cryptsetup")
lvm_path = shutil.which("lvm")
dm_crypt_loaded = Path("/sys/module/dm_crypt").is_dir() or Path("/proc/crypto").is_file()
live_session = Path("/rofs").is_dir() or Path("/cdrom/casper/filesystem.squashfs").is_file()

warnings = []
if arch != "x86_64":
    warnings.append(f"Unsupported architecture ({arch}); NEXUS OS targets x86_64.")
if ram_total_mib is not None and ram_total_mib < 850:
    warnings.append(f"Ultra-low RAM ({ram_total_mib} MiB); graphical Ubiquity requires >= 1024 MiB — use nexus-lite-install / nexus-disk-install CLI path.")
elif ram_total_mib is not None and ram_total_mib < 2048:
    warnings.append(f"Low RAM ({ram_total_mib} MiB); suitable for NEXUS Lite (>= 1024 MiB), while Cinnamon/Xfce require >= 2048 MiB (4096 MiB recommended).")
if not ubiquity_path:
    warnings.append("Linux Mint Ubiquity installer binary is not present on this host (live ISO required for graphical install).")
if not cryptsetup_path:
    warnings.append("cryptsetup binary not detected; LUKS full-disk encryption requires cryptsetup in live environment.")

eligible_disks = [d for d in disks if not d.get("removable")]

payload = {
    "arch": arch,
    "firmware": firmware,
    "live_session": live_session,
    "ubiquity_available": ubiquity_path is not None,
    "ubiquity_path": ubiquity_path,
    "secure_boot_status": {
        "uefi_active": uefi_active,
        "secure_boot_state": secure_boot,
        "shimx64_present": shim_present,
        "grub_efi_signed_present": grub_efi_signed_present,
        "grub_pc_bios_available": grub_pc_available,
    },
    "dual_boot_detection": {
        "os_prober_available": os_prober_path is not None,
        "esp_partitions": esp_partitions,
        "ntfs_partitions": ntfs_partitions,
        "existing_linux_partitions": linux_partitions,
        "luks_partitions": luks_partitions,
        "dual_boot_candidates_detected": bool(esp_partitions and (ntfs_partitions or linux_partitions)),
        "recommended_safe_flag": "--keep-efi --efi-part <ESP> --root-part <TARGET_PART>",
    },
    "encryption_ux": {
        "cryptsetup_available": cryptsetup_path is not None,
        "lvm2_available": lvm_path is not None,
        "luks_supported_via_ubiquity": bool(ubiquity_path and cryptsetup_path),
        "luks_supported_via_nexus_disk_install": cryptsetup_path is not None,
        "dm_crypt_module_ready": dm_crypt_loaded,
        "note": "nexus-disk-install --luks is verified end-to-end in disposable QEMU; Ubiquity interactive GUI LUKS/manual screens require manual GUI walkthrough.",
    },
    "installer_modes": {
        "guided_unencrypted_cli": "tested_qemu",
        "manual_partitioning_cli": "tested_qemu",
        "interrupted_recovery_cli": "tested_qemu",
        "guided_luks2_cli": "tested_qemu",
        "dual_boot_keep_efi_cli": "supported_qemu_simulated",
        "ubiquity_gui_interactive": "available_manual_gui" if ubiquity_path else "unavailable_in_lite_or_host",
        "legacy_bios_mbr": "unsupported_by_nexus_disk_install_uefi_required",
    },
    "hardware": {
        "cpu": cpu,
        "ram_total_mib": ram_total_mib,
        "root_free_gib": root_free_gib,
        "disks": disks,
        "non_removable_disk_count": len(eligible_disks),
        "gpus": gpus,
        "network": network_ifaces,
        "audio_cards": audio_cards,
        "displays": displays,
        "battery": battery,
    },
    "requirements": {
        "min_ram_mib": 1024,
        "lite_min_experimental_ram_mib": 512,
        "lite_recommended_ram_mib": 1024,
        "standard_min_ram_mib": 2048,
        "standard_recommended_ram_mib": 4096,
        "min_storage_gib": 20,
        "recommended_storage_gib": 32,
        "arch": "x86_64",
    },
    "warnings": warnings,
}

if fmt == "summary":
    print(f"NEXUS OS Install Preflight ({payload['arch']} / {payload['firmware']}, SecureBoot={secure_boot})")
    print(f"  CPU: {cpu}")
    print(f"  RAM: {ram_total_mib} MiB (Lite min {payload['requirements']['min_ram_mib']} MiB / Standard {payload['requirements']['standard_min_ram_mib']} MiB)")
    print(f"  Disks: {len(disks)} | ESPs: {len(esp_partitions)} | NTFS: {len(ntfs_partitions)} | LUKS: {len(luks_partitions)}")
    print(f"  LUKS CLI ready: {payload['encryption_ux']['luks_supported_via_nexus_disk_install']} | Ubiquity: {'available' if payload['ubiquity_available'] else 'unavailable'}")
    for w in warnings:
        print(f"  [WARN] {w}")
else:
    print(json.dumps(payload, indent=2))
PY
