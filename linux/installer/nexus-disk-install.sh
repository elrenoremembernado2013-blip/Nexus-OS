#!/usr/bin/env bash
# Safe, auditable live-to-disk installer for NEXUS OS (Linux Mint 22.3 / Noble).
# Designed for low-RAM CLI installation (NEXUS Lite 512M/768M) and automated
# disposable-disk VM testing without hardcoded credentials or host-disk risk.
set -euo pipefail

DISK=""
HOSTNAME_NEW="nexus-os"
USERNAME_NEW="nexus"
PASSWORD_HASH=""
PASSWORD_FILE=""
AUTOLOGIN=false
YES_ERASE=false
DRY_RUN=false
EDITION_OVERRIDE=""
LOG_FILE="/var/log/nexus-install.log"

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/installer/nexus-disk-install.sh --disk /dev/sdX [OPTIONS]

Installs the booted NEXUS OS live filesystem onto a target block device with
GPT + EFI System Partition (512 MiB FAT32) + ext4 root, UUID /etc/fstab,
initramfs regeneration, and UEFI GRUB bootloader.

Options:
  --disk DEV              Target block device (e.g. /dev/vda) [required]
  --hostname NAME         Installed system hostname (default: nexus-os)
  --user NAME             Primary sudo user to create (default: nexus)
  --password-hash HASH    Pre-hashed password (e.g. from openssl passwd -6)
  --password-file PATH    File containing plaintext password (read & hashed at runtime, never logged)
  --autologin             Configure LightDM autologin for the created user
  --edition NAME          Override edition metadata (lite | lite-lxqt | cinnamon | xfce)
  --yes-erase-disk        Required confirmation to partition and format --disk
  --dry-run               Print plan and safety checks without touching any disk
  --help, -h              Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --disk) [[ $# -ge 2 ]] || { echo '--disk requires a device path' >&2; exit 2; }; DISK="$2"; shift 2 ;;
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

if [[ "$DRY_RUN" == true || "$YES_ERASE" == false ]]; then
  echo "NEXUS Disk Installer Plan (dry-run / unconfirmed):"
  echo "  Target disk: $DISK"
  echo "  Partitioning: GPT -> 512 MiB FAT32 ESP (/boot/efi) + ext4 root (/)"
  echo "  User: $USERNAME_NEW (hostname: $HOSTNAME_NEW, autologin: $AUTOLOGIN)"
  echo "  Safety: Pass --yes-erase-disk as root inside a live ISO to execute."
  if [[ "$DRY_RUN" == true ]]; then
    exit 0
  fi
  echo 'Refusing destructive disk operation without --yes-erase-disk.' >&2
  exit 2
fi

[[ "$(id -u)" -eq 0 ]] || { echo 'Installation requires root privileges (sudo).' >&2; exit 1; }
[[ -b "$DISK" ]] || { printf 'Target is not a block device: %s\n' "$DISK" >&2; exit 1; }

# Safety check: refuse if target disk holds /, /rofs, /cdrom, or any active mount
if lsblk -n -o MOUNTPOINT "$DISK" 2>/dev/null | grep -qE '^(/|/rofs|/cdrom|/boot|/home)'; then
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
cleanup() {
  if [[ "$mounted" == true ]]; then
    umount -lf "$TARGET/dev/pts" 2>/dev/null || true
    umount -lf "$TARGET/dev" 2>/dev/null || true
    umount -lf "$TARGET/proc" 2>/dev/null || true
    umount -lf "$TARGET/sys" 2>/dev/null || true
    umount -lf "$TARGET/run" 2>/dev/null || true
    umount -lf "$TARGET/boot/efi" 2>/dev/null || true
    umount -lf "$TARGET" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log_msg() {
  local line
  line="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  printf '%s\n' "$line"
  mkdir -p -- "$(dirname "$LOG_FILE")"
  printf '%s\n' "$line" >> "$LOG_FILE"
}

log_msg "Starting NEXUS OS installation (edition=$EDITION disk=$DISK source=$SOURCE_MODE user=$USERNAME_NEW)"

# Partition disk (GPT: 512MiB EFI + rest ext4 root)
wipefs -af "$DISK" >/dev/null 2>&1 || true
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart root ext4 513MiB 100%
partprobe "$DISK" || true
udevadm settle || sleep 2

if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* || "$DISK" == *loop* ]]; then
  PART_EFI="${DISK}p1"
  PART_ROOT="${DISK}p2"
else
  PART_EFI="${DISK}1"
  PART_ROOT="${DISK}2"
fi

for _ in $(seq 1 15); do
  [[ -b "$PART_EFI" && -b "$PART_ROOT" ]] && break
  sleep 1
done
[[ -b "$PART_EFI" && -b "$PART_ROOT" ]] || { echo "Partitions did not appear on $DISK ($PART_EFI, $PART_ROOT)." >&2; exit 1; }

log_msg "Formatting $PART_EFI (FAT32) and $PART_ROOT (ext4)"
mkfs.vfat -F32 -n NEXUS_EFI "$PART_EFI" >/dev/null
mkfs.ext4 -F -E lazy_itable_init=1,lazy_journal_init=1 -L nexus_root "$PART_ROOT" >/dev/null

mkdir -p -- "$TARGET"
mount "$PART_ROOT" "$TARGET"
mounted=true
mkdir -p -- "$TARGET/boot/efi"
mount "$PART_EFI" "$TARGET/boot/efi"

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

uuid_root="$(blkid -s UUID -o value "$PART_ROOT")"
uuid_efi="$(blkid -s UUID -o value "$PART_EFI")"

cat > "$TARGET/etc/fstab" <<FSTAB
# /etc/fstab: static file system information for NEXUS OS
UUID=${uuid_root}  /          ext4  errors=remount-ro  0  1
UUID=${uuid_efi}   /boot/efi  vfat  umask=0077         0  1
FSTAB

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
  # Lock password only if neither hash nor file was provided; interactive login uses passwd
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
if [[ -f "$TARGET/boot/efi/EFI/BOOT/shimx64.efi" ]]; then
  mv -f -- "$TARGET/boot/efi/EFI/BOOT/shimx64.efi" "$TARGET/boot/efi/EFI/BOOT/BOOTX64.EFI"
elif [[ -f "$TARGET/boot/efi/EFI/BOOT/grubx64.efi" ]]; then
  cp -f -- "$TARGET/boot/efi/EFI/BOOT/grubx64.efi" "$TARGET/boot/efi/EFI/BOOT/BOOTX64.EFI"
fi

# Configure GRUB with clean timeout & console logging
if [[ -f "$TARGET/etc/default/grub" ]]; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' "$TARGET/etc/default/grub" || true
  sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' "$TARGET/etc/default/grub" || true
fi
chroot "$TARGET" /usr/sbin/update-grub

# Mark installed system metadata
cat > "$TARGET/etc/nexus-installed.json" <<META
{
  "edition": "${EDITION}",
  "disk": "${DISK}",
  "root_uuid": "${uuid_root}",
  "efi_uuid": "${uuid_efi}",
  "user": "${USERNAME_NEW}",
  "hostname": "${HOSTNAME_NEW}",
  "installed_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
META

sync
cleanup
mounted=false
log_msg "NEXUS OS installation completed cleanly on $DISK ($PART_ROOT)"
