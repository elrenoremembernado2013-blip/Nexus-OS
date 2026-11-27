#!/usr/bin/env bash
# Safe, read-only-by-default boot diagnostics and recovery guide for NEXUS OS.
# Never modifies partitions, filesystems, or bootloader configuration without
# explicit explanation and explicit user confirmation. Never logs secrets.
set -euo pipefail

MODE="diagnose"
FORMAT="text"
TOPIC="all"
PARTITION=""
CONFIRM=false
DRY_RUN=false
REDACTED=false

usage() {
  cat <<'USAGE'
Usage: bash linux/installer/nexus-recovery.sh [OPTIONS]

NEXUS OS Boot Diagnostics & Safe Recovery Tool.
Default behavior (--diagnose) is strictly read-only.

Options:
  --diagnose            Inspect UEFI/BIOS, Secure Boot, EFI files, fstab/crypttab,
                        block layout, failed services, and installer logs (read-only)
  --guide [TOPIC]       Print recovery steps: all | backup | grub | fsck | luks | packages | dualboot
  --fsck-dry-run        Preview or run a read-only filesystem check (fsck -n) on --partition
  --partition DEV       Target partition for --fsck-dry-run (e.g. /dev/vda2)
  --confirm             Required to execute --fsck-dry-run (always read-only -n)
  --dry-run             Explain intended command without executing
  --redacted            Omit filesystem UUIDs from text/JSON output
  --json                Emit diagnostic summary as JSON (with --diagnose)
  --help, -h            Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --diagnose) MODE="diagnose"; shift ;;
    --guide)
      MODE="guide"
      if [[ $# -ge 2 && "$2" != --* ]]; then
        TOPIC="$2"
        shift 2
      else
        shift
      fi
      ;;
    --fsck-dry-run) MODE="fsck_ro"; shift ;;
    --partition) [[ $# -ge 2 ]] || { echo '--partition requires a device path' >&2; exit 2; }; PARTITION="$2"; shift 2 ;;
    --confirm) CONFIRM=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --redacted) REDACTED=true; shift ;;
    --json) FORMAT="json"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

print_guide() {
  local topic="$1"
  case "$topic" in
    all|backup|grub|fsck|luks|packages|dualboot) ;;
    *)
      printf 'Unknown guide topic: %s (expected all | backup | grub | fsck | luks | packages | dualboot)\n' "$topic" >&2
      exit 2
      ;;
  esac

  if [[ "$topic" == "all" || "$topic" == "backup" ]]; then
    cat <<'TXT'
[1] SAFE BACKUP FIRST (DO THIS BEFORE ANY REPAIR)
  - Never run destructive partition tools before copying personal files off the drive.
  - Boot a NEXUS OS live USB/ISO and mount your partition READ-ONLY first:
      lsblk -f
      sudo mkdir -p /mnt/backup-ro
      sudo mount -o ro /dev/sdXY /mnt/backup-ro
  - For LUKS2 encrypted root, unlock read-only first if needed:
      sudo cryptsetup luksOpen --readonly /dev/sdXY nexus_ro
      sudo mount -o ro /dev/mapper/nexus_ro /mnt/backup-ro
  - Copy /mnt/backup-ro/home/<user>/ to an external USB drive before making any changes.
TXT
  fi

  if [[ "$topic" == "all" || "$topic" == "grub" ]]; then
    cat <<'TXT'

[2] BOOTLOADER & UEFI GRUB RECOVERY (FROM LIVE SESSION)
  - Confirm the live session is booted in UEFI mode (ls /sys/firmware/efi).
  - Identify your EFI System Partition (FAT32, ~512 MiB) and root partition (ext4 or LUKS2).
  - Mount root, /boot (if separate encrypted install), /boot/efi, and virtual filesystems:
      sudo mount /dev/sdX2 /mnt
      sudo mount /dev/sdX1 /mnt/boot/efi
      for d in dev dev/pts proc sys run; do sudo mount --bind "/$d" "/mnt/$d"; done
  - Reinstall UEFI GRUB and refresh signed Secure Boot chain + menu:
      sudo chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=nexus --recheck
      sudo chroot /mnt update-grub
  - If Secure Boot is enabled, verify /boot/efi/EFI/ubuntu/{shimx64.efi,grubx64.efi,grub.cfg}
    and /boot/efi/EFI/BOOT/BOOTX64.EFI exist.
TXT
  fi

  if [[ "$topic" == "all" || "$topic" == "fsck" ]]; then
    cat <<'TXT'

[3] FILESYSTEM CHECKING GUIDANCE (NEVER RUN WRITE-MODE FSCK ON A MOUNTED DISK)
  - Step A: Run a strictly read-only check first (safe to inspect errors without writing):
      sudo fsck -n /dev/sdXY
  - Step B: Unmount the partition before any repair (umount /dev/sdXY; never repair '/' while booted).
  - Step C: Only after backing up personal files and unmounting, run interactive/checked repair:
      sudo e2fsck -f -p /dev/sdXY    # for ext4 root or /boot
      sudo dosfsck -v /dev/sdX1      # for FAT32 EFI System Partition
TXT
  fi

  if [[ "$topic" == "all" || "$topic" == "luks" ]]; then
    cat <<'TXT'

[4] LUKS2 ENCRYPTED SYSTEM RECOVERY
  - Check LUKS2 header & active key slots (never exposes passphrases):
      sudo cryptsetup luksDump /dev/sdX3
  - Manually unlock from live USB to inspect /etc/crypttab and /etc/fstab:
      sudo cryptsetup luksOpen /dev/sdX3 nexus_crypt
      sudo mount /dev/mapper/nexus_crypt /mnt
  - Verify /etc/cryptsetup-initramfs/conf-hook contains 'CRYPTSETUP=y' and regenerate initramfs inside chroot:
      sudo chroot /mnt update-initramfs -u -k all
  - Back up your LUKS2 header offline after recovery:
      sudo cryptsetup luksHeaderBackup /dev/sdX3 --header-backup-file nexus-luks-header.img
TXT
  fi

  if [[ "$topic" == "all" || "$topic" == "packages" ]]; then
    cat <<'TXT'

[5] BROKEN PACKAGE / INTERRUPTED UPDATE REPAIR (INSTALLED SYSTEM OR CHROOT)
  - Complete half-configured packages first:
      sudo dpkg --configure -a
  - Fix missing dependencies using signed APT repositories:
      sudo apt-get update
      sudo apt-get install -f
      sudo apt-get check
TXT
  fi

  if [[ "$topic" == "all" || "$topic" == "dualboot" ]]; then
    cat <<'TXT'

[6] DUAL-BOOT PRESERVATION & RECOVERY
  - Never format an existing EFI System Partition shared with Windows or another OS.
  - When reinstalling NEXUS OS alongside another OS, pass `--keep-efi --efi-part <ESP> --root-part <PART>`
    to `nexus-disk-install`, or choose 'Something else' in Ubiquity and set the ESP mount point
    to `/boot/efi` with 'Format' UNCHECKED.
  - If an OS entry is missing from GRUB after install, ensure `GRUB_DISABLE_OS_PROBER=false` in
    `/etc/default/grub` and run `sudo update-grub`.
TXT
  fi
}

if [[ "$MODE" == "guide" ]]; then
  print_guide "$TOPIC"
  exit 0
fi

if [[ "$MODE" == "fsck_ro" ]]; then
  [[ -n "$PARTITION" ]] || { echo '--fsck-dry-run requires --partition /dev/sdXY.' >&2; exit 2; }
  echo "NEXUS Recovery — Read-Only Filesystem Check Plan"
  echo "  Intended action: Run 'fsck -n $PARTITION' (read-only inspection; makes ZERO changes to disk)."
  echo "  Why: Detects ext4/vfat metadata inconsistencies safely before deciding whether backup/repair is needed."
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] fsck -n $PARTITION"
    exit 0
  fi
  if [[ "$CONFIRM" == false ]]; then
    echo "Refusing execution without explicit --confirm (or pass --dry-run to preview)." >&2
    exit 2
  fi
  [[ -b "$PARTITION" ]] || { printf 'Partition does not exist: %s\n' "$PARTITION" >&2; exit 1; }
  command -v fsck >/dev/null 2>&1 || { echo 'fsck tool is unavailable.' >&2; exit 1; }
  exec fsck -n "$PARTITION"
fi

# --diagnose mode (strictly read-only)
python3 - "$FORMAT" "$REDACTED" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

fmt = sys.argv[1]
redacted = sys.argv[2] == "true"


def read_text(path: Path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def redact_line(text: str) -> str:
    if not redacted:
        return text
    return re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "<REDACTED_UUID>", text)


uefi_active = Path("/sys/firmware/efi").is_dir()
live_session = Path("/rofs").is_dir() or Path("/cdrom/casper/filesystem.squashfs").is_file()

edition = "unknown"
rel = read_text(Path("/etc/nexus-os-release"))
if rel:
    for line in rel.splitlines():
        if line.startswith("NEXUS_EDITION="):
            edition = line.split("=", 1)[1].strip().strip('"')

secure_boot = "unavailable"
if uefi_active and Path("/sys/firmware/efi/efivars").is_dir():
    for cand in sorted(Path("/sys/firmware/efi/efivars").glob("SecureBoot-*")):
        try:
            data = cand.read_bytes()
            if len(data) >= 5:
                secure_boot = "enabled" if data[4] == 1 else "disabled"
                break
        except OSError:
            pass

efi_paths = {
    "boot_x64": Path("/boot/efi/EFI/BOOT/BOOTX64.EFI").is_file(),
    "ubuntu_shim": Path("/boot/efi/EFI/ubuntu/shimx64.efi").is_file(),
    "ubuntu_grub": Path("/boot/efi/EFI/ubuntu/grubx64.efi").is_file(),
    "ubuntu_grub_cfg": Path("/boot/efi/EFI/ubuntu/grub.cfg").is_file(),
    "nexus_grub": Path("/boot/efi/EFI/nexus/grubx64.efi").is_file(),
    "nexus_grub_cfg": Path("/boot/efi/EFI/nexus/grub.cfg").is_file(),
}

fstab_issues = []
fstab_text = read_text(Path("/etc/fstab"))
if fstab_text is not None:
    for idx, raw in enumerate(fstab_text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) < 4:
            fstab_issues.append(f"Line {idx}: malformed fstab entry (< 4 fields)")
            continue
        spec = fields[0]
        if spec.startswith("UUID=") and shutil.which("blkid"):
            uuid_val = spec.split("=", 1)[1]
            try:
                res = subprocess.run(["blkid", "-U", uuid_val], capture_output=True, text=True, timeout=5)
                if res.returncode != 0:
                    fstab_issues.append(f"Line {idx}: UUID not currently detected by blkid")
            except Exception:
                pass
elif not live_session:
    fstab_issues.append("/etc/fstab missing or unreadable")

crypttab_entries = 0
crypttab_issues = []
crypttab_text = read_text(Path("/etc/crypttab"))
if crypttab_text:
    for idx, raw in enumerate(crypttab_text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        crypttab_entries += 1
        fields = line.split()
        if len(fields) < 3:
            crypttab_issues.append(f"Line {idx}: malformed crypttab entry (< 3 fields)")

failed_units = []
if shutil.which("systemctl"):
    try:
        res = subprocess.run(["systemctl", "--failed", "--no-legend", "--plain"], capture_output=True, text=True, timeout=3)
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                line = line.strip()
                if line:
                    failed_units.append(line.split()[0])
    except Exception:
        pass

disks_summary = []
if shutil.which("lsblk"):
    try:
        res = subprocess.run(["lsblk", "-J", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT"], capture_output=True, text=True, timeout=3)
        if res.returncode == 0 and res.stdout.strip():
            disks_summary = json.loads(res.stdout).get("blockdevices", [])
    except Exception:
        pass

installer_logs = [
    p for p in (
        "/var/log/nexus-install.log",
        "/var/log/installer/syslog",
        "/var/log/installer/debug",
    ) if Path(p).is_file()
]

findings = []
if not uefi_active and not live_session:
    findings.append("System is not booted via UEFI (/sys/firmware/efi absent); UEFI GRUB repair requires UEFI boot.")
if uefi_active and not live_session and not (efi_paths["boot_x64"] or efi_paths["ubuntu_grub"] or efi_paths["nexus_grub"]):
    findings.append("UEFI ESP bootloader binaries under /boot/efi/EFI are missing or unmounted.")
if fstab_issues:
    findings.extend(fstab_issues)
if crypttab_issues:
    findings.extend(crypttab_issues)
if failed_units:
    findings.append(f"Failed systemd units detected: {', '.join(failed_units)}")

payload = {
    "read_only": True,
    "edition": edition,
    "environment": "live_session" if live_session else "installed_or_host",
    "uefi_active": uefi_active,
    "secure_boot_state": secure_boot,
    "efi_paths": efi_paths,
    "fstab_issues": [redact_line(x) for x in fstab_issues],
    "crypttab_entries": crypttab_entries,
    "crypttab_issues": [redact_line(x) for x in crypttab_issues],
    "failed_systemd_units": failed_units,
    "installer_logs_present": installer_logs,
    "block_devices_count": len(disks_summary),
    "findings": [redact_line(x) for x in findings],
    "recommended_next_step": "Run `nexus-recovery --guide` for safe backup, GRUB, fsck, LUKS2, and package recovery steps.",
}

if fmt == "json":
    print(json.dumps(payload, indent=2))
else:
    print(f"NEXUS OS Recovery Diagnosis (read-only | edition={edition} | env={payload['environment']})")
    print(f"  Firmware: {'UEFI' if uefi_active else 'Legacy/Container'} | Secure Boot: {secure_boot}")
    print(f"  Installer logs present: {', '.join(installer_logs) if installer_logs else 'none'}")
    print(f"  fstab issues: {len(fstab_issues)} | crypttab entries: {crypttab_entries} (issues={len(crypttab_issues)}) | failed units: {len(failed_units)}")
    if findings:
        print("  Diagnostic findings:")
        for f in payload["findings"]:
            print(f"    - {f}")
    else:
        print("  Diagnostic findings: none (no boot/fstab/crypttab/systemd errors detected on current host)")
    print("  Next: Run `bash linux/installer/nexus-recovery.sh --guide` for safe, step-by-step recovery procedures.")
PY
