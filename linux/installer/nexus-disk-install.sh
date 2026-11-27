#!/usr/bin/env bash
# Safe, auditable live-to-disk installer for NEXUS OS (Linux Mint 22.3 / Noble).
# Supports guided GPT+UEFI, manual partition selection (--efi-part / --root-part),
# optional LUKS2 full-disk encryption (--luks --luks-passphrase-file), and
# interrupted-install recovery without hardcoded credentials or host-disk risk.
set -euo pipefail

DISK=""
EFI_PART=""
ROOT_PART=""
KEEP_EFI=false
LUKS_ENABLED=false
LUKS_PASS_FILE=""
HOSTNAME_NEW="nexus-os"
USERNAME_NEW="nexus"
PASSWORD_HASH=""
PASSWORD_FILE=""
AUTOLOGIN=false
YES_ERASE=false
DRY_RUN=false
EDITION_OVERRIDE=""
LOG_FILE="/var/log/nexus-install.log"
CRYPT_NAME="nexus_crypt"

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/installer/nexus-disk-install.sh --disk /dev/sdX [OPTIONS]

Installs the booted NEXUS OS live filesystem onto a target block device with
UEFI FAT32 ESP + ext4 root (or LUKS2 encrypted root with separate /boot),
UUID /etc/fstab, initramfs regeneration, and UEFI GRUB bootloader.

Options:
  --disk DEV                    Target block device (e.g. /dev/vda) [required]
  --efi-part DEV                Use pre-created EFI System Partition (manual partitioning)
  --root-part DEV               Use pre-created root partition (manual partitioning)
  --keep-efi                    Do not reformat --efi-part (preserve existing EFI files)
  --luks                        Enable LUKS2 root encryption (creates ESP + /boot + LUKS2 /)
  --luks-passphrase-file PATH   File containing LUKS passphrase (read & removed by caller, never logged)
  --hostname NAME               Installed system hostname (default: nexus-os)
  --user NAME                   Primary sudo user to create (default: nexus)
  --password-hash HASH          Pre-hashed password (e.g. from openssl passwd -6)
  --password-file PATH          File containing plaintext password (read & hashed at runtime, never logged)
  --autologin                   Configure LightDM autologin for the created user
  --edition NAME                Override edition metadata (lite | lite-lxqt | cinnamon | xfce)
  --yes-erase-disk              Required confirmation to format/install onto target
  --dry-run                     Print plan and safety checks without touching any disk
  --help, -h                    Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --disk) [[ $# -ge 2 ]] || { echo '--disk requires a device path' >&2; exit 2; }; DISK="$2"; shift 2 ;;
    --efi-part) [[ $# -ge 2 ]] || { echo '--efi-part requires a device path' >&2; exit 2; }; EFI_PART="$2"; shift 2 ;;
    --root-part) [[ $# -ge 2 ]] || { echo '--root-part requires a device path' >&2; exit 2; }; ROOT_PART="$2"; shift 2 ;;
    --keep-efi) KEEP_EFI=true; shift ;;
    --luks) LUKS_ENABLED=true; shift ;;
    --luks-passphrase-file) [[ $# -ge 2 ]] || { echo '--luks-passphrase-file requires a path' >&2; exit 2; }; LUKS_PASS_FILE="$2"; shift 2 ;;
    --hostname) [[ $# -ge 2 ]] || { echo '--hostname requires a value' >&2; exit 2; }; HOSTNAME_NEW="$2"; shift 2 ;;
    --user) [[ $# -ge 2 ]] || { echo '--user requires a value' >&2; exit 2; }; USERNAME_NEW="$2"; shift 2 ;;
    --password-hash) [[ $# -ge 2 ]] || { echo '--password-hash requires a hash' >&2; exit 2; }; PASSWORD_HASH="$2"; shift 2 ;;
    --password-file) [[ $# -ge 2 ]] || { echo '--password-file requires a path' >&2; exit 2; }; PASSWORD_FILE="$2"; shift 2 ;;
    --autologin) AUTOLOGIN=true; shift ;;
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION_OVERRIDE="$2"; shift 2 ;;
    --yes-erase-disk) YES_ERASE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$DISK" ]] || { echo 'Missing --disk /dev/... argument.' >&2; usage >&2; exit 2; }
[[ "$HOSTNAME_NEW" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || { echo 'Invalid --hostname.' >&2; exit 2; }
[[ "$USERNAME_NEW" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo 'Invalid --user.' >&2; exit 2; }

if [[ -n "$EDITION_OVERRIDE" ]]; then
  case "$EDITION_OVERRIDE" in
    standard) EDITION_OVERRIDE="cinnamon" ;;
    cinnamon|xfce|lite|lite-lxqt) ;;
    *) printf 'Unsupported --edition: %s (expected cinnamon | xfce | lite | lite-lxqt)\n' "$EDITION_OVERRIDE" >&2; exit 2 ;;
  esac
fi

if [[ -n "$EFI_PART" || -n "$ROOT_PART" ]]; then
  [[ -n "$EFI_PART" && -n "$ROOT_PART" ]] || { echo 'Manual partitioning requires both --efi-part and --root-part.' >&2; exit 2; }
  [[ "$EFI_PART" != "$ROOT_PART" ]] || { echo '--efi-part and --root-part must be distinct partitions.' >&2; exit 2; }
fi

if [[ "$KEEP_EFI" == true && -z "$EFI_PART" ]]; then
  echo '--keep-efi requires explicit --efi-part and --root-part.' >&2
  exit 2
fi

if [[ "$LUKS_ENABLED" == true && -n "$EFI_PART" ]]; then
  echo '--luks automated layout currently requires whole-disk guided partitioning (cannot combine with --efi-part).' >&2
  exit 2
fi

if [[ "$DRY_RUN" == true || "$YES_ERASE" == false ]]; then
  echo "NEXUS Disk Installer Plan (dry-run / unconfirmed):"
  echo "  Target disk: $DISK"
  if [[ -n "$EFI_PART" ]]; then
    echo "  Partitioning: Manual -> EFI=$EFI_PART (keep=$KEEP_EFI), root=$ROOT_PART (ext4)"
  elif [[ "$LUKS_ENABLED" == true ]]; then
    echo "  Partitioning: GPT -> 512 MiB FAT32 ESP (/boot/efi) + 1024 MiB ext4 (/boot) + LUKS2 encrypted root (/)"
  else
    echo "  Partitioning: Guided GPT -> 512 MiB FAT32 ESP (/boot/efi) + ext4 root (/)"
  fi
  echo "  User: $USERNAME_NEW (hostname: $HOSTNAME_NEW, autologin: $AUTOLOGIN, luks: $LUKS_ENABLED)"
  echo "  Safety: Pass --yes-erase-disk as root inside a live ISO to execute."
  if [[ "$DRY_RUN" == true ]]; then
    exit 0
  fi
  echo 'Refusing destructive disk operation without --yes-erase-disk.' >&2
  exit 2
fi

[[ "$(id -u)" -eq 0 ]] || { echo 'Installation requires root privileges (sudo).' >&2; exit 1; }
[[ -b "$DISK" ]] || { printf 'Target is not a block device: %s\n' "$DISK" >&2; exit 1; }

# Safety check: refuse if target disk holds /, /rofs, /cdrom, or any active host mount
if lsblk -n -o MOUNTPOINT "$DISK" 2>/dev/null | grep -qE '^(/|/rofs|/cdrom|/boot|/home)$'; then
  printf 'SAFETY ABORT: %s has active system mountpoints!\n' "$DISK" >&2
  exit 1
fi
disk_type="$(lsblk -n -d -o TYPE "$DISK" 2>/dev/null || true)"
[[ "$disk_type" == "disk" ]] || { printf 'SAFETY ABORT: %s is type=%s, expected disk.\n' "$DISK" "$disk_type" >&2; exit 1; }
disk_bytes="$(lsblk -n -d -b -o SIZE "$DISK" 2>/dev/null || echo 0)"
(( disk_bytes >= 10737418240 )) || { printf 'SAFETY ABORT: %s is < 10 GiB (%s bytes).\n' "$DISK" "$disk_bytes" >&2; exit 1; }

# Determine live source
SOURCE_MODE=""
SQUASH_FILE="/cdrom/casper/filesystem.squashfs"
if [[ -d /rofs/etc && -d /rofs/usr ]]; then
  SOURCE_MODE="rofs"
elif [[ -r "$SQUASH_FILE" ]]; then
  SOURCE_MODE="squashfs"
else
  echo 'Neither /rofs nor /cdrom/casper/filesystem.squashfs is available; run from a live NEXUS ISO.' >&2
  exit 1
fi

for cmd in parted mkfs.vfat mkfs.ext4 blkid chroot grub-install update-grub; do
  command -v "$cmd" >/dev/null 2>&1 || { printf 'Missing required installer tool: %s\n' "$cmd" >&2; exit 1; }
done

if [[ "$LUKS_ENABLED" == true ]]; then
  command -v cryptsetup >/dev/null 2>&1 || { echo 'Missing required cryptsetup tool for --luks.' >&2; exit 1; }
  [[ -n "$LUKS_PASS_FILE" && -r "$LUKS_PASS_FILE" ]] || { echo '--luks requires a readable --luks-passphrase-file PATH.' >&2; exit 2; }
  [[ -s "$LUKS_PASS_FILE" ]] || { echo '--luks-passphrase-file cannot be empty.' >&2; exit 2; }
  if [[ -z "$(tr -d '\r\n[:space:]' < "$LUKS_PASS_FILE")" ]]; then
    echo '--luks-passphrase-file cannot contain only whitespace or newlines.' >&2
    exit 2
  fi
fi

if [[ -n "$PASSWORD_FILE" ]]; then
  [[ -r "$PASSWORD_FILE" ]] || { printf 'Password file unreadable: %s\n' "$PASSWORD_FILE" >&2; exit 1; }
  if command -v openssl >/dev/null 2>&1; then
    PASSWORD_HASH="$(openssl passwd -6 -stdin < "$PASSWORD_FILE")"
  else
    PASSWORD_HASH="$(python3 -c 'import crypt,sys; print(crypt.crypt(sys.stdin.read().rstrip("\r\n"), crypt.mksalt(crypt.METHOD_SHA512)))' < "$PASSWORD_FILE")"
  fi
fi

# Detect edition if not overridden
EDITION="$EDITION_OVERRIDE"
if [[ -z "$EDITION" && -r /etc/nexus-os-release ]]; then
  EDITION="$(awk -F= '/^NEXUS_EDITION=/{gsub(/"/,"",$2); print $2}' /etc/nexus-os-release || true)"
fi
EDITION="${EDITION:-lite}"

TARGET="/mnt/nexus-install-target"
mounted=false
crypt_opened=false
CURRENT_STAGE="preflight"
DISK_MODIFIED=false

log_msg() {
  local line
  line="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  printf '%s\n' "$line"
  mkdir -p -- "$(dirname "$LOG_FILE")"
  printf '%s\n' "$line" >> "$LOG_FILE"
}

cleanup() {
  if [[ "$mounted" == true ]]; then
    umount -lf "$TARGET/dev/pts" 2>/dev/null || true
    umount -lf "$TARGET/dev" 2>/dev/null || true
    umount -lf "$TARGET/proc" 2>/dev/null || true
    umount -lf "$TARGET/sys" 2>/dev/null || true
    umount -lf "$TARGET/run" 2>/dev/null || true
    umount -lf "$TARGET/boot/efi" 2>/dev/null || true
    umount -lf "$TARGET/boot" 2>/dev/null || true
    umount -lf "$TARGET" 2>/dev/null || true
    mounted=false
  fi
  if [[ "$crypt_opened" == true ]] && command -v cryptsetup >/dev/null 2>&1; then
    cryptsetup luksClose "$CRYPT_NAME" 2>/dev/null || true
    crypt_opened=false
  fi
}

on_err() {
  local rc=$?
  printf 'ERROR: NEXUS OS installation failed during stage [%s] (exit=%s).\n' "$CURRENT_STAGE" "$rc" >&2
  printf '  Disk modified: %s | Target: %s\n' "$DISK_MODIFIED" "$DISK" >&2
  printf '  Temporary mounts and any LUKS mapper are being safely detached.\n' >&2
  printf '  Recovery guidance:\n' >&2
  printf '    1. Inspect logs: %s\n' "$LOG_FILE" >&2
  printf '    2. Inspect partitions safely (read-only): lsblk -f\n' >&2
  printf '    3. Run recovery diagnostics: nexus-recovery --diagnose\n' >&2
  exit "$rc"
}
trap cleanup EXIT
trap on_err ERR

# Interrupted-install recovery: detach any stale mounts or LUKS mapper left by a previous aborted run
if mountpoint -q "$TARGET" 2>/dev/null || [[ -d "$TARGET/boot" ]]; then
  log_msg "Recovering from prior stale target mounts under $TARGET"
  mounted=true
  cleanup
  mounted=false
fi
if [[ -e "/dev/mapper/$CRYPT_NAME" ]] && command -v cryptsetup >/dev/null 2>&1; then
  log_msg "Closing stale LUKS mapper /dev/mapper/$CRYPT_NAME"
  cryptsetup luksClose "$CRYPT_NAME" 2>/dev/null || true
fi

is_manual=false
layout_name="guided"
if [[ -n "$EFI_PART" ]]; then
  is_manual=true
  layout_name="manual"
elif [[ "$LUKS_ENABLED" == true ]]; then
  layout_name="guided_luks2"
fi

log_msg "Starting NEXUS OS installation (edition=$EDITION disk=$DISK source=$SOURCE_MODE user=$USERNAME_NEW luks=$LUKS_ENABLED manual=$is_manual)"

PART_BOOT=""
PART_LUKS=""
LUKS_UUID=""

if [[ -n "$EFI_PART" ]]; then
  # Manual partitioning path: validate existing partitions and preserve partition table
  CURRENT_STAGE="manual_partition_validation"
  [[ -b "$EFI_PART" && -b "$ROOT_PART" ]] || { echo "Specified manual partitions do not exist ($EFI_PART, $ROOT_PART)." >&2; exit 1; }
  [[ "$(lsblk -n -d -o TYPE "$EFI_PART" 2>/dev/null || true)" == "part" ]] || { echo "$EFI_PART is not a partition." >&2; exit 1; }
  [[ "$(lsblk -n -d -o TYPE "$ROOT_PART" 2>/dev/null || true)" == "part" ]] || { echo "$ROOT_PART is not a partition." >&2; exit 1; }

  disk_real="$(readlink -f "$DISK")"
  efi_pk="$(lsblk -n -d -o PKNAME "$EFI_PART" 2>/dev/null || true)"
  root_pk="$(lsblk -n -d -o PKNAME "$ROOT_PART" 2>/dev/null || true)"
  [[ -n "$efi_pk" && "$(readlink -f "/dev/$efi_pk")" == "$disk_real" ]] || {
    printf 'SAFETY ABORT: --efi-part (%s) does not belong to target --disk (%s).\n' "$EFI_PART" "$DISK" >&2
    exit 1
  }
  [[ -n "$root_pk" && "$(readlink -f "/dev/$root_pk")" == "$disk_real" ]] || {
    printf 'SAFETY ABORT: --root-part (%s) does not belong to target --disk (%s).\n' "$ROOT_PART" "$DISK" >&2
    exit 1
  }

  if lsblk -n -o MOUNTPOINT "$EFI_PART" 2>/dev/null | grep -qE '^/'; then
    printf 'SAFETY ABORT: --efi-part (%s) is currently mounted.\n' "$EFI_PART" >&2
    exit 1
  fi
  if lsblk -n -o MOUNTPOINT "$ROOT_PART" 2>/dev/null | grep -qE '^/'; then
    printf 'SAFETY ABORT: --root-part (%s) is currently mounted.\n' "$ROOT_PART" >&2
    exit 1
  fi

  root_bytes="$(lsblk -n -d -b -o SIZE "$ROOT_PART" 2>/dev/null || echo 0)"
  (( root_bytes >= 8589934592 )) || {
    printf 'SAFETY ABORT: --root-part (%s) is < 8 GiB (%s bytes).\n' "$ROOT_PART" "$root_bytes" >&2
    exit 1
  }

  PART_EFI="$EFI_PART"
  PART_ROOT="$ROOT_PART"
  if [[ "$KEEP_EFI" == false ]]; then
    CURRENT_STAGE="filesystem_format"
    DISK_MODIFIED=true
    log_msg "Formatting manual EFI partition $PART_EFI (FAT32)"
    mkfs.vfat -F32 -n NEXUS_EFI "$PART_EFI" >/dev/null
  else
    efi_fstype="$(blkid -s TYPE -o value "$PART_EFI" 2>/dev/null || true)"
    [[ "$efi_fstype" == "vfat" ]] || {
      printf 'SAFETY ABORT: --keep-efi expects a FAT32/vfat EFI System Partition, found fstype=%s on %s.\n' "${efi_fstype:-unknown}" "$PART_EFI" >&2
      exit 1
    }
    log_msg "Preserving existing manual EFI partition $PART_EFI (--keep-efi, fstype=$efi_fstype)"
  fi
  CURRENT_STAGE="filesystem_format"
  DISK_MODIFIED=true
  log_msg "Formatting manual root partition $PART_ROOT (ext4)"
  mkfs.ext4 -F -E lazy_itable_init=1,lazy_journal_init=1 -L nexus_root "$PART_ROOT" >/dev/null
else
  # Guided partitioning (standard or LUKS2)
  CURRENT_STAGE="partitioning"
  DISK_MODIFIED=true
  wipefs -af "$DISK" >/dev/null 2>&1 || true
  parted -s "$DISK" mklabel gpt
  parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
  parted -s "$DISK" set 1 esp on
  if [[ "$LUKS_ENABLED" == true ]]; then
    parted -s "$DISK" mkpart boot ext4 513MiB 1537MiB
    parted -s "$DISK" mkpart cryptroot ext4 1537MiB 100%
  else
    parted -s "$DISK" mkpart root ext4 513MiB 100%
  fi
  partprobe "$DISK" || true
  udevadm settle || sleep 2

  if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* || "$DISK" == *loop* ]]; then
    PART_EFI="${DISK}p1"
    if [[ "$LUKS_ENABLED" == true ]]; then
      PART_BOOT="${DISK}p2"
      PART_LUKS="${DISK}p3"
    else
      PART_ROOT="${DISK}p2"
    fi
  else
    PART_EFI="${DISK}1"
    if [[ "$LUKS_ENABLED" == true ]]; then
      PART_BOOT="${DISK}2"
      PART_LUKS="${DISK}3"
    else
      PART_ROOT="${DISK}2"
    fi
  fi

  for _ in $(seq 1 15); do
    if [[ "$LUKS_ENABLED" == true ]]; then
      [[ -b "$PART_EFI" && -b "$PART_BOOT" && -b "$PART_LUKS" ]] && break
    else
      [[ -b "$PART_EFI" && -b "$PART_ROOT" ]] && break
    fi
    sleep 1
  done

  if [[ "$LUKS_ENABLED" == true ]]; then
    [[ -b "$PART_EFI" && -b "$PART_BOOT" && -b "$PART_LUKS" ]] || { echo "LUKS partitions did not appear on $DISK." >&2; exit 1; }
    CURRENT_STAGE="filesystem_format"
    log_msg "Formatting $PART_EFI (FAT32) and $PART_BOOT (ext4 /boot)"
    mkfs.vfat -F32 -n NEXUS_EFI "$PART_EFI" >/dev/null
    mkfs.ext4 -F -E lazy_itable_init=1,lazy_journal_init=1 -L nexus_boot "$PART_BOOT" >/dev/null
    CURRENT_STAGE="luks_format"
    log_msg "Formatting $PART_LUKS as LUKS2 (argon2id 64 MiB memory bound for low-RAM reliability)"
    tr -d '\r\n' < "$LUKS_PASS_FILE" | cryptsetup luksFormat \
      --type luks2 \
      --cipher aes-xts-plain64 \
      --key-size 512 \
      --hash sha256 \
      --pbkdf argon2id \
      --pbkdf-memory 65536 \
      --iter-time 400 \
      --batch-mode \
      --key-file - \
      "$PART_LUKS"
    tr -d '\r\n' < "$LUKS_PASS_FILE" | cryptsetup luksOpen --key-file - "$PART_LUKS" "$CRYPT_NAME"
    crypt_opened=true
    PART_ROOT="/dev/mapper/$CRYPT_NAME"
    LUKS_UUID="$(blkid -s UUID -o value "$PART_LUKS")"
    log_msg "Formatting decrypted root $PART_ROOT (ext4)"
    mkfs.ext4 -F -E lazy_itable_init=1,lazy_journal_init=1 -L nexus_root "$PART_ROOT" >/dev/null
  else
    [[ -b "$PART_EFI" && -b "$PART_ROOT" ]] || { echo "Partitions did not appear on $DISK ($PART_EFI, $PART_ROOT)." >&2; exit 1; }
    CURRENT_STAGE="filesystem_format"
    log_msg "Formatting $PART_EFI (FAT32) and $PART_ROOT (ext4)"
    mkfs.vfat -F32 -n NEXUS_EFI "$PART_EFI" >/dev/null
    mkfs.ext4 -F -E lazy_itable_init=1,lazy_journal_init=1 -L nexus_root "$PART_ROOT" >/dev/null
  fi
fi

CURRENT_STAGE="mounting"
mkdir -p -- "$TARGET"
mount "$PART_ROOT" "$TARGET"
mounted=true
if [[ -n "$PART_BOOT" ]]; then
  mkdir -p -- "$TARGET/boot"
  mount "$PART_BOOT" "$TARGET/boot"
fi
mkdir -p -- "$TARGET/boot/efi"
mount "$PART_EFI" "$TARGET/boot/efi"

CURRENT_STAGE="filesystem_copy"
log_msg "Copying live filesystem ($SOURCE_MODE) to $TARGET"
if [[ "$SOURCE_MODE" == "rofs" ]]; then
  cp -a /rofs/. "$TARGET/"
else
  unsquashfs -f -d "$TARGET" "$SQUASH_FILE"
fi

mkdir -p -- "$TARGET/dev" "$TARGET/dev/pts" "$TARGET/proc" "$TARGET/sys" "$TARGET/run" "$TARGET/tmp"
chmod 1777 "$TARGET/tmp"
mount --bind /dev "$TARGET/dev"
mount --bind /dev/pts "$TARGET/dev/pts"
mount -t proc proc "$TARGET/proc"
mount -t sysfs sysfs "$TARGET/sys"
mount --bind /run "$TARGET/run"

CURRENT_STAGE="system_config"
uuid_root="$(blkid -s UUID -o value "$PART_ROOT")"
uuid_efi="$(blkid -s UUID -o value "$PART_EFI")"

if [[ "$LUKS_ENABLED" == true ]]; then
  uuid_boot="$(blkid -s UUID -o value "$PART_BOOT")"
  cat > "$TARGET/etc/crypttab" <<CRYPTTAB
# <target name> <source device> <key file> <options>
${CRYPT_NAME} UUID=${LUKS_UUID} none luks,discard
CRYPTTAB
  cat > "$TARGET/etc/fstab" <<FSTAB
# /etc/fstab: static file system information for NEXUS OS (LUKS2 encrypted root)
/dev/mapper/${CRYPT_NAME}  /          ext4  errors=remount-ro  0  1
UUID=${uuid_boot}          /boot      ext4  defaults           0  2
UUID=${uuid_efi}           /boot/efi  vfat  umask=0077         0  1
FSTAB
  mkdir -p -- "$TARGET/etc/cryptsetup-initramfs" "$TARGET/usr/local/share/nexus-os"
  printf 'CRYPTSETUP=y\n' > "$TARGET/etc/cryptsetup-initramfs/conf-hook"
  cat > "$TARGET/usr/local/share/nexus-os/luks-recovery-guide.txt" <<GUIDE
NEXUS OS LUKS2 Recovery Guide
=============================
1. Back up the LUKS2 header to external offline storage immediately after install:
     sudo cryptsetup luksHeaderBackup /dev/disk/by-uuid/${LUKS_UUID} --header-backup-file nexus-luks-header.img
2. Add a secondary recovery passphrase in an unused key slot:
     sudo cryptsetup luksAddKey /dev/disk/by-uuid/${LUKS_UUID}
3. Inspect key slots without exposing secrets:
     sudo cryptsetup luksDump /dev/disk/by-uuid/${LUKS_UUID}
4. If the system cannot unlock automatically on boot, boot a NEXUS live ISO and run:
     sudo cryptsetup luksOpen /dev/disk/by-uuid/${LUKS_UUID} ${CRYPT_NAME}
GUIDE
  chmod 0644 "$TARGET/usr/local/share/nexus-os/luks-recovery-guide.txt"
else
  cat > "$TARGET/etc/fstab" <<FSTAB
# /etc/fstab: static file system information for NEXUS OS
UUID=${uuid_root}  /          ext4  errors=remount-ro  0  1
UUID=${uuid_efi}   /boot/efi  vfat  umask=0077         0  1
FSTAB
fi

printf '%s\n' "$HOSTNAME_NEW" > "$TARGET/etc/hostname"
cat > "$TARGET/etc/hosts" <<HOSTS
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME_NEW}
::1       localhost ip6-localhost ip6-loopback
HOSTS

# Remove live-only casper artifacts and ensure zero test services leak
rm -f -- "$TARGET/etc/casper.conf" \
  "$TARGET/etc/systemd/system/nexus-test-agent.service" \
  "$TARGET/etc/systemd/system/multi-user.target.wants/nexus-test-agent.service"
rm -rf -- "$TARGET/usr/local/libexec/nexus-test"

# Remove live user autologin overrides from casper if present (keep session defaults)
rm -f -- "$TARGET/etc/lightdm/lightdm.conf.d/casper.conf" || true
for dm_cfg in "$TARGET/etc/lightdm/lightdm.conf" "$TARGET/etc/lightdm/lightdm.conf.d/70-linuxmint.conf"; do
  if [[ -f "$dm_cfg" ]]; then
    sed -i '/^autologin-user=/d;/^autologin-user-timeout=/d' "$dm_cfg" || true
  fi
done

# Create target user (never hardcoding passwords in script)
chroot "$TARGET" /usr/sbin/userdel -r mint >/dev/null 2>&1 || true
if ! chroot "$TARGET" /usr/bin/id "$USERNAME_NEW" >/dev/null 2>&1; then
  chroot "$TARGET" /usr/sbin/useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev "$USERNAME_NEW"
fi
if [[ -n "$PASSWORD_HASH" ]]; then
  printf '%s:%s\n' "$USERNAME_NEW" "$PASSWORD_HASH" | chroot "$TARGET" /usr/sbin/chpasswd -e
else
  chroot "$TARGET" /usr/bin/passwd -d "$USERNAME_NEW" >/dev/null 2>&1 || true
fi

if [[ "$AUTOLOGIN" == true ]]; then
  mkdir -p -- "$TARGET/etc/lightdm/lightdm.conf.d"
  cat > "$TARGET/etc/lightdm/lightdm.conf.d/95-nexus-installed-autologin.conf" <<DM
[Seat:*]
autologin-user=${USERNAME_NEW}
autologin-user-timeout=0
DM
fi

CURRENT_STAGE="initramfs"
# Remove casper/ubiquity live-only packages before regenerating initramfs
chroot "$TARGET" env DEBIAN_FRONTEND=noninteractive dpkg --purge --no-triggers casper lupin-casper >/dev/null 2>&1 || true

# Ensure kernel & initramfs are present in /boot for update-grub
if ! compgen -G "$TARGET/boot/vmlinuz-*" >/dev/null; then
  if [[ -r /cdrom/casper/vmlinuz ]]; then
    kver="$(find "$TARGET/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n1)"
    cp -f /cdrom/casper/vmlinuz "$TARGET/boot/vmlinuz-${kver}"
  fi
fi
initrd_speed_conf="$TARGET/etc/initramfs-tools/conf.d/99-nexus-fast-initrd.conf"
mkdir -p -- "$TARGET/etc/initramfs-tools/conf.d"
printf 'COMPRESS=gzip\nCOMPRESSLEVEL=1\n' > "$initrd_speed_conf"
if ! compgen -G "$TARGET/boot/initrd.img-*" >/dev/null; then
  chroot "$TARGET" /usr/sbin/update-initramfs -c -k all
else
  chroot "$TARGET" /usr/sbin/update-initramfs -u -k all
fi
rm -f -- "$initrd_speed_conf"

CURRENT_STAGE="bootloader_install"
# Install UEFI GRUB bootloader + fallback EFI/BOOT/BOOTX64.EFI
log_msg "Installing UEFI GRUB bootloader onto $DISK ($PART_EFI)"
chroot "$TARGET" /usr/sbin/grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=nexus \
  --recheck \
  --no-nvram

mkdir -p -- "$TARGET/boot/efi/EFI/BOOT" "$TARGET/boot/efi/EFI/ubuntu"
cp -a "$TARGET/boot/efi/EFI/nexus/." "$TARGET/boot/efi/EFI/BOOT/"
# Signed Ubuntu/Mint grubx64.efi looks for /EFI/ubuntu/grub.cfg even when --bootloader-id=nexus
cp -a "$TARGET/boot/efi/EFI/nexus/." "$TARGET/boot/efi/EFI/ubuntu/"
# Ensure signed UEFI Secure Boot chain (shimx64.efi -> grubx64.efi -> signed kernel) when available
if [[ -f "$TARGET/boot/efi/EFI/BOOT/shimx64.efi" ]]; then
  mv -f -- "$TARGET/boot/efi/EFI/BOOT/shimx64.efi" "$TARGET/boot/efi/EFI/BOOT/BOOTX64.EFI"
elif [[ -f "$TARGET/usr/lib/shim/shimx64.efi.signed" ]]; then
  cp -f -- "$TARGET/usr/lib/shim/shimx64.efi.signed" "$TARGET/boot/efi/EFI/BOOT/BOOTX64.EFI"
  cp -f -- "$TARGET/usr/lib/shim/shimx64.efi.signed" "$TARGET/boot/efi/EFI/nexus/shimx64.efi"
  cp -f -- "$TARGET/usr/lib/shim/shimx64.efi.signed" "$TARGET/boot/efi/EFI/ubuntu/shimx64.efi"
  if [[ -f "$TARGET/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ]]; then
    cp -f -- "$TARGET/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" "$TARGET/boot/efi/EFI/BOOT/grubx64.efi"
    cp -f -- "$TARGET/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" "$TARGET/boot/efi/EFI/nexus/grubx64.efi"
    cp -f -- "$TARGET/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" "$TARGET/boot/efi/EFI/ubuntu/grubx64.efi"
  fi
  for aux_efi in mmx64.efi fbx64.efi; do
    if [[ -f "$TARGET/usr/lib/shim/$aux_efi" ]]; then
      cp -f -- "$TARGET/usr/lib/shim/$aux_efi" "$TARGET/boot/efi/EFI/BOOT/$aux_efi"
      cp -f -- "$TARGET/usr/lib/shim/$aux_efi" "$TARGET/boot/efi/EFI/ubuntu/$aux_efi"
    fi
  done
elif [[ -f "$TARGET/boot/efi/EFI/BOOT/grubx64.efi" ]]; then
  cp -f -- "$TARGET/boot/efi/EFI/BOOT/grubx64.efi" "$TARGET/boot/efi/EFI/BOOT/BOOTX64.EFI"
fi

# Configure GRUB with clean timeout & console logging
if [[ -f "$TARGET/etc/default/grub" ]]; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' "$TARGET/etc/default/grub" || true
  sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' "$TARGET/etc/default/grub" || true
  if [[ "$KEEP_EFI" == true ]]; then
    sed -i '/^#*GRUB_DISABLE_OS_PROBER=/d' "$TARGET/etc/default/grub" || true
    printf 'GRUB_DISABLE_OS_PROBER=false\n' >> "$TARGET/etc/default/grub"
  fi
fi
chroot "$TARGET" /usr/sbin/update-grub

CURRENT_STAGE="finalizing"
# Mark installed system metadata (zero secrets or passphrases stored)
cat > "$TARGET/etc/nexus-installed.json" <<META
{
  "edition": "${EDITION}",
  "disk": "${DISK}",
  "layout": "${layout_name}",
  "encrypted": ${LUKS_ENABLED},
  "luks_uuid": "${LUKS_UUID}",
  "root_uuid": "${uuid_root}",
  "efi_uuid": "${uuid_efi}",
  "user": "${USERNAME_NEW}",
  "hostname": "${HOSTNAME_NEW}",
  "installed_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
META

sync
cleanup
log_msg "NEXUS OS installation completed successfully (edition=${EDITION}, layout=${layout_name}, disk=${DISK})."
echo "Next steps: Remove the live USB/ISO media and reboot into the installed system."
if [[ "$LUKS_ENABLED" == true ]]; then
  echo "LUKS2 note: You will be prompted for your encryption passphrase at boot. See /usr/local/share/nexus-os/luks-recovery-guide.txt."
fi
