#!/usr/bin/env bash
# Read-only hardware, firmware, storage, dual-boot, Secure Boot, edition, and
# installer readiness probe for NEXUS OS (Linux Mint 22.3 / Ubuntu Noble).
# Never alters partitions, disks, or system state.
set -euo pipefail

FORMAT="json"
EDITION_OVERRIDE=""

usage() {
  cat <<'USAGE'
Usage: bash linux/installer/nexus-install-preflight.sh [OPTIONS]

Reports real hardware, active NEXUS edition, VM vs bare-metal environment,
firmware (UEFI/BIOS), Secure Boot chain, block storage sizes/types, dual-boot
candidates, required installer tools, network readiness, and structured
warnings (problem, why it matters, whether install can continue, action).
Strictly read-only.

Options:
  --json            Print JSON output (default)
  --summary         Print human-readable preflight summary instead of JSON
  --edition NAME    Override detected edition (cinnamon | xfce | lite | lite-lxqt)
  --help, -h        Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --json) FORMAT="json"; shift ;;
    --summary) FORMAT="summary"; shift ;;
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION_OVERRIDE="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$FORMAT" "$EDITION_OVERRIDE" <<'PY'
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

fmt = sys.argv[1]
edition_override = sys.argv[2].strip().lower()


def read_text(path: Path):
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


def detect_edition():
    if edition_override:
        return "cinnamon" if edition_override == "standard" else edition_override
    rel = read_text(Path("/etc/nexus-os-release"))
    if rel:
        vals = {}
        for line in rel.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                vals[k.strip()] = v.strip().strip('"').strip("'").lower()
        if vals.get("NEXUS_EDITION"):
            return vals["NEXUS_EDITION"]
        if vals.get("NEXUS_DESKTOP"):
            return vals["NEXUS_DESKTOP"]
    return "unknown"


edition = detect_edition()
arch = platform.machine()
uefi_active = Path("/sys/firmware/efi").is_dir()
firmware = "UEFI" if uefi_active else "BIOS/Legacy (or container)"

# Virtual machine vs bare-metal detection (read-only DMI/sysfs/systemd-detect-virt)
virt_type = "none"
if shutil.which("systemd-detect-virt"):
    try:
        vres = subprocess.run(["systemd-detect-virt"], capture_output=True, text=True, timeout=2)
        if vres.stdout.strip():
            virt_type = vres.stdout.strip()
    except Exception:
        pass
if virt_type == "none":
    sys_vendor = (read_text(Path("/sys/class/dmi/id/sys_vendor")) or "").lower()
    product_name = (read_text(Path("/sys/class/dmi/id/product_name")) or "").lower()
    if "qemu" in sys_vendor or "qemu" in product_name or "bochs" in sys_vendor:
        virt_type = "qemu"
    elif "virtualbox" in product_name or "innotek" in sys_vendor:
        virt_type = "oracle"
    elif "vmware" in sys_vendor:
        virt_type = "vmware"
    elif Path("/.dockerenv").exists():
        virt_type = "container"

is_vm = virt_type not in ("none", "")
is_qemu = "qemu" in virt_type or "kvm" in virt_type

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
ram_available_mib = None
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
                ram_available_mib = round(int(tok) / 1024)

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
            ["lsblk", "-b", "-J", "-o", "NAME,SIZE,MODEL,TYPE,FSTYPE,PARTTYPENAME,RO,RM,TRAN,ROTA"],
            capture_output=True,
            text=True,
            timeout=4,
        )
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)

            def fmt_size(sz_val):
                try:
                    b = int(sz_val)
                    return round(b / (1024 ** 3), 1)
                except (TypeError, ValueError):
                    return None

            def classify_disk(dev):
                name = str(dev.get("name") or "")
                tran = str(dev.get("tran") or "").lower()
                rota = dev.get("rota")
                if name.startswith("nvme") or tran == "nvme":
                    return "nvme_ssd"
                if name.startswith("mmcblk"):
                    return "emmc_or_sd"
                if name.startswith("vd"):
                    return "virtio_virtual_disk"
                if rota in (False, 0, "0"):
                    return "sata_or_usb_ssd"
                if rota in (True, 1, "1"):
                    return "hdd_rotational"
                return tran or "unknown"

            def walk_parts(node):
                for ch in node.get("children", []) or []:
                    ptype = ch.get("type")
                    name = f"/dev/{ch.get('name')}"
                    fstype = (ch.get("fstype") or "").lower()
                    parttype = (ch.get("parttypename") or "").lower()
                    size_gib = fmt_size(ch.get("size"))
                    if ptype in ("part", "crypt"):
                        rec = {
                            "device": name,
                            "size": f"{size_gib}G" if size_gib is not None else str(ch.get("size") or "unknown"),
                            "size_gib": size_gib,
                            "fstype": fstype or "unknown",
                        }
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
                    size_gib = fmt_size(dev.get("size"))
                    disks.append({
                        "device": f"/dev/{dev.get('name')}",
                        "size": f"{size_gib}G" if size_gib is not None else str(dev.get("size") or "unknown"),
                        "size_gib": size_gib,
                        "model": (dev.get("model") or "").strip() or "Unknown",
                        "transport": (dev.get("tran") or "").strip() or "unknown",
                        "drive_type": classify_disk(dev),
                        "removable": bool(dev.get("rm")),
                        "read_only": bool(dev.get("ro")),
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
up_network_ifaces = []
try:
    net_devs = sorted(Path("/sys/class/net").iterdir()) if Path("/sys/class/net").is_dir() else []
except OSError:
    net_devs = []
for iface in net_devs:
    if iface.name == "lo":
        continue
    state = read_text(iface / "operstate") or "unknown"
    rec = {"name": iface.name, "state": state}
    network_ifaces.append(rec)
    if state == "up":
        up_network_ifaces.append(iface.name)

default_route_present = False
route_text = read_text(Path("/proc/net/route"))
if route_text:
    for line in route_text.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "00000000":
            default_route_present = True
            break

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

required_tools = {
    "parted": shutil.which("parted") is not None,
    "mkfs.vfat": shutil.which("mkfs.vfat") is not None,
    "mkfs.ext4": shutil.which("mkfs.ext4") is not None,
    "blkid": shutil.which("blkid") is not None,
    "grub-install": shutil.which("grub-install") is not None,
    "update-grub": shutil.which("update-grub") is not None,
    "cryptsetup": cryptsetup_path is not None,
    "os-prober": os_prober_path is not None,
    "efibootmgr": shutil.which("efibootmgr") is not None,
    "ubiquity": ubiquity_path is not None,
}
missing_cli_tools = [t for t in ("parted", "mkfs.vfat", "mkfs.ext4", "blkid", "grub-install") if not required_tools[t]]

eligible_disks = [d for d in disks if not d.get("removable") and not d.get("read_only")]
eligible_disks_ge_20gib = [d for d in eligible_disks if (d.get("size_gib") or 0) >= 20.0]
eligible_disks_ge_10gib = [d for d in eligible_disks if (d.get("size_gib") or 0) >= 10.0]

edition_min_ram = 2048
edition_rec_ram = 4096
if edition == "lite":
    edition_min_ram = 512
    edition_rec_ram = 1024
elif edition == "lite-lxqt":
    edition_min_ram = 1024
    edition_rec_ram = 2048

structured_warnings = []


def add_warning(wid, severity, problem, why_it_matters, can_continue, recommended_action):
    structured_warnings.append({
        "id": wid,
        "severity": severity,
        "problem": problem,
        "why_it_matters": why_it_matters,
        "can_continue": can_continue,
        "recommended_action": recommended_action,
    })


if arch != "x86_64":
    add_warning(
        "unsupported_arch",
        "blocker",
        f"Unsupported CPU architecture ({arch}).",
        "NEXUS OS ISOs, kernels, and signed EFI bootloaders target x86_64 (amd64) only.",
        False,
        "Boot on an x86_64 PC or QEMU x86_64 virtual machine.",
    )

if ram_total_mib is not None:
    if ram_total_mib < 512:
        add_warning(
            "critical_low_ram",
            "blocker",
            f"System RAM is {ram_total_mib} MiB (below the 512 MiB NEXUS Lite experimental floor).",
            "Kernel, squashfs extraction, and APT/dpkg post-install steps will fail or OOM-freeze below 512 MiB.",
            False,
            "Increase RAM to at least 512 MiB (CLI Lite) or 1024+ MiB (recommended).",
        )
    elif edition in ("cinnamon", "xfce") and ram_total_mib < 2048:
        add_warning(
            "insufficient_ram_for_standard_edition",
            "warning",
            f"RAM is {ram_total_mib} MiB, below the 2048 MiB minimum for NEXUS {edition}.",
            "Cinnamon/Xfce and Ubiquity GTK can thrash swap or stall during installation under 2048 MiB.",
            True,
            "Use NEXUS Lite (Openbox) or NEXUS Lite (LXQt) on 512-1024 MiB devices, or increase VM/device RAM to >= 2048 MiB.",
        )
    elif ram_total_mib < 850:
        add_warning(
            "ultra_low_ram_gui_warning",
            "warning",
            f"Ultra-low RAM ({ram_total_mib} MiB): graphical Ubiquity requires >= 1024 MiB.",
            "Ubiquity GTK + X11 can exhaust RAM on 512-768 MiB systems while installing packages.",
            True,
            "Use `sudo nexus-lite-install` / `nexus-disk-install` CLI installer instead of Ubiquity GTK.",
        )
    elif edition == "lite-lxqt" and ram_total_mib < 1024:
        add_warning(
            "low_ram_lxqt_warning",
            "warning",
            f"RAM is {ram_total_mib} MiB, below the 1024 MiB minimum tier for NEXUS Lite LXQt.",
            "LXQt desktop + installation performs best at >= 1024 MiB; 512-768 MiB belongs to Openbox Lite.",
            True,
            "Use NEXUS Lite (Openbox) for 512-768 MiB systems or allocate >= 1024 MiB for Lite LXQt.",
        )

if not uefi_active:
    add_warning(
        "non_uefi_boot",
        "warning",
        f"System is not booted in UEFI mode (detected: {firmware}).",
        "nexus-disk-install enforces GPT + FAT32 EFI System Partition + UEFI GRUB and refuses Legacy BIOS/MBR writes to avoid breaking legacy boot setups.",
        bool(ubiquity_path),
        "Enable UEFI boot (OVMF in QEMU or UEFI in bare-metal firmware) before running UEFI installation.",
    )
elif secure_boot == "enabled" and not (shim_present and grub_efi_signed_present):
    add_warning(
        "secure_boot_missing_signed_chain",
        "warning",
        "UEFI Secure Boot is enabled, but signed shimx64.efi or grubx64.efi.signed is missing.",
        "Without shim-signed + grub-efi-amd64-signed, an installed system will be rejected by UEFI Secure Boot firmware on reboot.",
        True,
        "Install `shim-signed` and `grub-efi-amd64-signed` in the live image before installing, or verify Secure Boot chain with `nexus-recovery --diagnose`.",
    )

if not disks:
    add_warning(
        "no_disks_detected",
        "blocker",
        "No block disks were detected by lsblk.",
        "An installation requires a writable target block device (e.g., NVMe, SATA, or virtual qcow2 disk).",
        False,
        "Attach a virtual qcow2 disk in QEMU or verify storage controller visibility before retrying.",
    )
elif not eligible_disks_ge_10gib:
    add_warning(
        "insufficient_disk_capacity",
        "blocker",
        "No non-removable writable disk >= 10 GiB was detected.",
        "The NEXUS OS root filesystem and EFI System Partition require at least 10 GiB minimum (20+ GiB recommended).",
        False,
        "Attach or free a non-removable disk of at least 20 GiB (32+ GiB recommended).",
    )
elif not eligible_disks_ge_20gib:
    add_warning(
        "tight_disk_capacity",
        "warning",
        "Eligible disk is between 10 GiB and 20 GiB (below the 20 GiB recommended minimum).",
        "Limited free space leaves little headroom for updates, logs, or swap/user files after installation.",
        True,
        "Use a >= 20 GiB disk (32+ GiB recommended) for general use.",
    )

if esp_partitions and (ntfs_partitions or linux_partitions):
    add_warning(
        "dual_boot_os_detected",
        "info",
        f"Existing OS partitions detected ({len(esp_partitions)} EFI, {len(ntfs_partitions)} NTFS, {len(linux_partitions)} Linux).",
        "Erasing the whole disk would destroy existing operating systems and user data on those partitions.",
        True,
        "Back up existing data first, then use manual partitioning (`--keep-efi --efi-part <ESP> --root-part <PART>` or Ubiquity 'Something else').",
    )

if not ubiquity_path:
    add_warning(
        "ubiquity_unavailable",
        "warning",
        "Linux Mint Ubiquity GUI installer is not installed in this environment.",
        "Graphical installation cannot launch outside a Mint/NEXUS live ISO with Ubiquity present.",
        True,
        "Boot a built NEXUS OS live ISO for Ubiquity GUI installation, or use `nexus-disk-install` CLI from a live squashfs session.",
    )

if not cryptsetup_path:
    add_warning(
        "cryptsetup_unavailable",
        "warning",
        "cryptsetup is not available in this environment.",
        "LUKS2 full-disk encryption setup and encrypted recovery unlock cannot run without cryptsetup.",
        True,
        "Install `cryptsetup` and `cryptsetup-initramfs` if full-disk encryption is required.",
    )

if missing_cli_tools:
    add_warning(
        "missing_cli_installer_tools",
        "warning",
        f"Missing core disk installer tools: {', '.join(missing_cli_tools)}.",
        "Partitioning, formatting, or UEFI GRUB installation cannot execute without these system utilities.",
        bool(ubiquity_path),
        "Ensure core manifest packages (`parted`, `dosfstools`, `grub-efi-amd64-bin`) are installed.",
    )

if not default_route_present and not up_network_ifaces:
    add_warning(
        "offline_environment",
        "info",
        "No active network link or default route detected.",
        "Offline live-ISO installation from local squashfs still works, but online updates, third-party codecs, and post-install APT/Flatpak steps require network access.",
        True,
        "Connect Ethernet or Wi-Fi if you want updates/optional apps, or proceed offline with local squashfs installation.",
    )

blockers = [w for w in structured_warnings if not w["can_continue"]]
warnings = [f"[{w['severity'].upper()}] {w['problem']} -> {w['recommended_action']}" for w in structured_warnings if w["severity"] in ("blocker", "warning")]
requirements_satisfied = len(blockers) == 0

eligible_disk_count = len(eligible_disks)

payload = {
    "arch": arch,
    "edition": edition,
    "firmware": firmware,
    "environment": {
        "is_virtual_machine": is_vm,
        "is_qemu": is_qemu,
        "virt_type": virt_type,
        "label": f"Virtual Machine ({virt_type})" if is_vm else "Bare Metal (physical or chroot)",
    },
    "live_session": live_session,
    "ubiquity_available": ubiquity_path is not None,
    "ubiquity_path": ubiquity_path,
    "requirements_satisfied": requirements_satisfied,
    "can_continue_cli": requirements_satisfied and uefi_active and len(missing_cli_tools) == 0,
    "can_continue_gui": requirements_satisfied and ubiquity_path is not None and (ram_total_mib is None or ram_total_mib >= 850),
    "required_tools": required_tools,
    "missing_cli_tools": missing_cli_tools,
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
        "note": "nexus-disk-install --luks is verified end-to-end in disposable QEMU; Ubiquity interactive GUI LUKS/manual screens require GUI/CI walkthrough.",
    },
    "installer_modes": {
        "guided_unencrypted_cli": "tested_qemu",
        "manual_partitioning_cli": "tested_qemu",
        "interrupted_recovery_cli": "tested_qemu",
        "guided_luks2_cli": "tested_qemu",
        "dual_boot_keep_efi_cli": "tested_qemu_simulated",
        "secure_boot_ovmf_cli": "tested_qemu_ovmf_secboot",
        "ubiquity_gui_interactive": "launch_verified_in_qemu_walkthrough_in_ci" if ubiquity_path else "unavailable_in_lite_or_host",
        "physical_bare_metal_install": "untested_bare_metal",
        "legacy_bios_mbr": "unsupported_by_nexus_disk_install_uefi_required",
    },
    "hardware": {
        "cpu": cpu,
        "ram_total_mib": ram_total_mib,
        "ram_available_mib": ram_available_mib,
        "root_free_gib": root_free_gib,
        "disks": disks,
        "non_removable_disk_count": eligible_disk_count,
        "eligible_disks_ge_10gib": len(eligible_disks_ge_10gib),
        "eligible_disks_ge_20gib": len(eligible_disks_ge_20gib),
        "gpus": gpus,
        "network": network_ifaces,
        "online_network": {
            "up_interfaces": up_network_ifaces,
            "default_route_present": default_route_present,
            "offline_live_install_supported": True,
        },
        "audio_cards": audio_cards,
        "displays": displays,
        "battery": battery,
    },
    "requirements": {
        "edition": edition,
        "edition_min_ram_mib": edition_min_ram,
        "edition_recommended_ram_mib": edition_rec_ram,
        "min_ram_mib": 1024,
        "lite_min_experimental_ram_mib": 512,
        "lite_recommended_ram_mib": 1024,
        "standard_min_ram_mib": 2048,
        "standard_recommended_ram_mib": 4096,
        "min_storage_gib": 20,
        "absolute_min_storage_gib": 10,
        "recommended_storage_gib": 32,
        "arch": "x86_64",
    },
    "blockers": blockers,
    "structured_warnings": structured_warnings,
    "warnings": warnings,
}

if fmt == "summary":
    print(f"NEXUS OS Install Preflight ({payload['arch']} / edition={edition} / {payload['firmware']} / SecureBoot={secure_boot})")
    print(f"  Environment: {payload['environment']['label']}")
    print(f"  CPU: {cpu}")
    print(f"  RAM: {ram_total_mib} MiB total, {ram_available_mib} MiB available (Edition min {edition_min_ram} MiB / rec {edition_rec_ram} MiB)")
    print(f"  Disks: {len(disks)} ({len(eligible_disks_ge_20gib)} >= 20 GiB) | ESPs: {len(esp_partitions)} | NTFS: {len(ntfs_partitions)} | LUKS: {len(luks_partitions)}")
    print(f"  Network: up={len(up_network_ifaces)}, default_route={default_route_present} (offline live install supported)")
    print(f"  Readiness: requirements_satisfied={requirements_satisfied} | CLI_ready={payload['can_continue_cli']} | GUI_ready={payload['can_continue_gui']}")
    for w in structured_warnings:
        print(f"  [{w['severity'].upper()}] {w['problem']}")
        print(f"    Why: {w['why_it_matters']}")
        print(f"    Can continue: {w['can_continue']} | Action: {w['recommended_action']}")
else:
    print(json.dumps(payload, indent=2))
PY
