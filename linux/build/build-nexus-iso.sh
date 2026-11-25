#!/usr/bin/env bash
# Reproducible Linux Mint 22.3 Xfce live-ISO builder for NEXUS OS.
# Unpacks a GPG- and SHA-256-verified Mint ISO, applies NEXUS config/branding/
# packages inside an isolated squashfs staging tree under build/iso/, repacks a
# hybrid BIOS+UEFI ISO via xorriso, and records build-info.json + SHA-256.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SYSTEM_CONF="$REPO_ROOT/linux/config/nexus-system.conf"
PKG_MANIFEST="$REPO_ROOT/linux/config/mint-packages.list"
PREREQ_SCRIPT="$SCRIPT_DIR/check-build-prereqs.sh"

DOWNLOAD_DIR="${NEXUS_DOWNLOAD_DIR:-$REPO_ROOT/build/downloads}"
BASE_ISO="${NEXUS_BASE_ISO:-$DOWNLOAD_DIR/linuxmint-22.3-xfce-64bit.iso}"
MANIFEST_FILE="${NEXUS_BASE_MANIFEST:-$DOWNLOAD_DIR/sha256sum.txt}"
WORK_DIR="${NEXUS_ISO_WORK_DIR:-$REPO_ROOT/build/iso/work}"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"

DRY_RUN=false
CHECK_ONLY=false
WITH_GAMING=false
WITH_DEV=false

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/build/build-nexus-iso.sh [OPTIONS]

Prepares and builds a Linux Mint 22.3 Xfce based NEXUS OS live ISO under
build/iso/out/ from an already verified Mint ISO (scripts/download-linux-mint.sh).

Options:
  --check        Check host build prerequisites and exit
  --dry-run      Validate configuration and print exact build steps without root or tools
  --with-gaming  Include gaming packages from linux/config/mint-packages.list
  --with-dev     Include development packages from linux/config/mint-packages.list
  --help, -h     Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --with-gaming) WITH_GAMING=true; shift ;;
    --with-dev) WITH_DEV=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -r "$SYSTEM_CONF" ]] || { printf 'Missing system config: %s\n' "$SYSTEM_CONF" >&2; exit 1; }
[[ -r "$PKG_MANIFEST" ]] || { printf 'Missing package manifest: %s\n' "$PKG_MANIFEST" >&2; exit 1; }

if [[ "$CHECK_ONLY" == true ]]; then
  exec bash "$PREREQ_SCRIPT"
fi

conf_version="22.3"
conf_edition="xfce"
conf_arch="x86_64"
while IFS='=' read -r key val; do
  case "$key" in
    NEXUS_BASE_VERSION) conf_version="$val" ;;
    NEXUS_BASE_EDITION) conf_edition="$val" ;;
    NEXUS_TARGET_ARCH) conf_arch="$val" ;;
  esac
done < "$SYSTEM_CONF"

iso_arch="amd64"
if [[ "$conf_arch" != "x86_64" ]]; then
  iso_arch="$conf_arch"
fi
OUT_ISO="$OUT_DIR/nexus-os-${conf_version}-${conf_edition}-${iso_arch}.iso"

packages=()
while IFS=':' read -r category pkg; do
  [[ -z "${category:-}" || "$category" == \#* ]] && continue
  pkg="${pkg%%[[:space:]]*}"
  [[ -n "$pkg" ]] || continue
  case "$category" in
    core|desktop|nexus) packages+=("$pkg") ;;
    gaming) [[ "$WITH_GAMING" == true ]] && packages+=("$pkg") ;;
    development) [[ "$WITH_DEV" == true ]] && packages+=("$pkg") ;;
    optional) ;;
  esac
done < "$PKG_MANIFEST"

if [[ "$DRY_RUN" == true ]]; then
  echo "NEXUS OS ISO Build Plan (dry-run)"
  echo "  Base ISO: $BASE_ISO"
  echo "  Manifest: $MANIFEST_FILE"
  echo "  Work dir: $WORK_DIR"
  echo "  Output ISO: $OUT_ISO"
  echo "  Packages (${#packages[@]}): ${packages[*]}"
  echo "Step 1: bash $PREREQ_SCRIPT --strict"
  echo "Step 2: Verify $BASE_ISO SHA-256 against $MANIFEST_FILE"
  echo "Step 3: Extract ISO tree via xorriso into $WORK_DIR/iso-root and unpack casper/filesystem.squashfs via unsquashfs"
  echo "Step 4: Mount dev/proc/sys in $WORK_DIR/squashfs-root, install packages, and apply NEXUS branding + provisioning"
  echo "Step 5: Repack casper/filesystem.squashfs via mksquashfs -comp xz and update casper/filesystem.size + md5sum.txt"
  echo "Step 6: Repack hybrid BIOS+UEFI ISO with xorriso to $OUT_ISO and generate .sha256 + build-info.json"
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo 'ISO building requires root privileges for squashfs/chroot operations. Use --dry-run or --check for unprivileged inspection.' >&2
  exit 1
fi

bash "$PREREQ_SCRIPT" --strict
[[ -r "$MANIFEST_FILE" ]] || { printf 'Missing signed checksum manifest: %s (run bash scripts/download-linux-mint.sh)\n' "$MANIFEST_FILE" >&2; exit 1; }

iso_basename="${BASE_ISO##*/}"
expected_line="$(grep -F " ${iso_basename}" "$MANIFEST_FILE" | head -n 1 || true)"
[[ -n "$expected_line" ]] || { printf 'No entry for %s in %s\n' "$iso_basename" "$MANIFEST_FILE" >&2; exit 1; }
expected_sha="${expected_line%% *}"
actual_sha="$(sha256sum "$BASE_ISO" | awk '{print $1}')"
if [[ "$expected_sha" != "$actual_sha" ]]; then
  printf 'Base ISO SHA-256 mismatch: expected %s, got %s\n' "$expected_sha" "$actual_sha" >&2
  exit 1
fi

iso_root="$WORK_DIR/iso-root"
squash_root="$WORK_DIR/squashfs-root"
mounted_chroot=false

cleanup() {
  if [[ "$mounted_chroot" == true ]]; then
    umount -lf "$squash_root/dev/pts" 2>/dev/null || true
    umount -lf "$squash_root/dev" 2>/dev/null || true
    umount -lf "$squash_root/proc" 2>/dev/null || true
    umount -lf "$squash_root/sys" 2>/dev/null || true
    umount -lf "$squash_root/run" 2>/dev/null || true
  fi
}
trap cleanup EXIT

rm -rf -- "$iso_root" "$squash_root"
mkdir -p -- "$iso_root" "$OUT_DIR"

xorriso -osirrox on -indev "$BASE_ISO" -extract / "$iso_root"
chmod -R u+w "$iso_root"
unsquashfs -d "$squash_root" "$iso_root/casper/filesystem.squashfs"

mount --bind /dev "$squash_root/dev"
mount --bind /dev/pts "$squash_root/dev/pts"
mount -t proc proc "$squash_root/proc"
mount -t sysfs sysfs "$squash_root/sys"
mount --bind /run "$squash_root/run"
mounted_chroot=true

mkdir -p -- "$squash_root/tmp/nexus-repo"
cp -a "$REPO_ROOT/linux" "$squash_root/tmp/nexus-repo/linux"

chroot_args=(--skip-ufw --autostart-firstboot --force)
[[ "$WITH_GAMING" == true ]] && chroot_args+=(--with-gaming)
[[ "$WITH_DEV" == true ]] && chroot_args+=(--with-dev)

chroot "$squash_root" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
  bash /tmp/nexus-repo/linux/mint/provision-nexus-guest.sh "${chroot_args[@]}"
chroot "$squash_root" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
  apt-get clean
rm -rf -- "$squash_root/tmp/nexus-repo"

cleanup
mounted_chroot=false

rm -f -- "$iso_root/casper/filesystem.squashfs"
mksquashfs "$squash_root" "$iso_root/casper/filesystem.squashfs" -comp xz -noappend
printf '%s\n' "$(du -sx --block-size=1 "$squash_root" | awk '{print $1}')" > "$iso_root/casper/filesystem.size"

(
  cd "$iso_root"
  rm -f md5sum.txt
  find . -type f ! -path './isolinux/*' -print0 | xargs -0 md5sum > md5sum.txt
)

xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid "NEXUS_OS_${conf_version}" \
  -eltorito-boot isolinux/isolinux.bin \
  -eltorito-catalog isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -output "$OUT_ISO" \
  "$iso_root"

(
  cd "$OUT_DIR"
  sha256sum "${OUT_ISO##*/}" > "${OUT_ISO##*/}.sha256"
)

built_sha="$(awk '{print $1}' "${OUT_ISO}.sha256")"
cat > "$OUT_DIR/build-info.json" <<JSON
{
  "name": "NEXUS OS",
  "base_distro": "linuxmint",
  "base_version": "${conf_version}",
  "edition": "${conf_edition}",
  "arch": "${iso_arch}",
  "base_iso": "${iso_basename}",
  "base_iso_sha256": "${actual_sha}",
  "output_iso": "${OUT_ISO##*/}",
  "output_iso_sha256": "${built_sha}",
  "with_gaming": ${WITH_GAMING},
  "with_dev": ${WITH_DEV},
  "built_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

printf 'Built NEXUS OS ISO: %s\n' "$OUT_ISO"
