#!/usr/bin/env bash
# Reproducible Linux Mint 22.3 live-ISO builder for NEXUS OS (Standard Cinnamon,
# MADOO Xfce, and Lite Openbox editions kept strictly isolated).
set -eEuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PREREQ_SCRIPT="$SCRIPT_DIR/check-build-prereqs.sh"
VALIDATE_PKGS="$SCRIPT_DIR/validate-packages.sh"
BRANDING_SCRIPT="$SCRIPT_DIR/apply-iso-branding.sh"

EDITION="${NEXUS_EDITION:-xfce}"
EDITION_SET=false
DRY_RUN=false
CHECK_ONLY=false
WITH_GAMING=false
WITH_DEV=false

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/build/build-nexus-iso.sh [OPTIONS]

Prepares and builds a Linux Mint 22.3 based NEXUS OS live ISO under
build/iso/out/ from a verified Mint ISO (scripts/download-linux-mint.sh).

Options:
  --edition NAME  cinnamon | standard | xfce | lite | lite-lxqt (default: xfce unless NEXUS_EDITION set)
  --check         Check host build prerequisites and exit
  --dry-run       Validate configuration and print exact build steps without root or tools
  --with-gaming   Include gaming packages (Standard/Xfce only)
  --with-dev      Include development packages (Standard/Xfce only)
  --help, -h      Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; EDITION_SET=true; shift 2 ;;
    --check) CHECK_ONLY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --with-gaming) WITH_GAMING=true; shift ;;
    --with-dev) WITH_DEV=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$EDITION" in
  standard|cinnamon)
    default_conf="$REPO_ROOT/linux/config/nexus-standard-cinnamon.conf"
    default_manifest="$REPO_ROOT/linux/config/cinnamon-packages.list"
    default_provision="linux/mint/provision-nexus-guest.sh"
    default_base_iso="linuxmint-22.3-cinnamon-64bit.iso"
    default_work="work-cinnamon"
    ;;
  xfce)
    default_conf="$REPO_ROOT/linux/config/nexus-system.conf"
    default_manifest="$REPO_ROOT/linux/config/mint-packages.list"
    default_provision="linux/mint/provision-nexus-guest.sh"
    default_base_iso="linuxmint-22.3-xfce-64bit.iso"
    default_work="work-xfce"
    ;;
  lite)
    default_conf="$REPO_ROOT/linux/lite/nexus-lite.conf"
    default_manifest="$REPO_ROOT/linux/lite/lite-packages.list"
    default_provision="linux/lite/provision-nexus-lite.sh"
    default_base_iso="linuxmint-22.3-xfce-64bit.iso"
    default_work="work-lite"
    ;;
  lite-lxqt)
    default_conf="$REPO_ROOT/linux/lite/nexus-lite-lxqt.conf"
    default_manifest="$REPO_ROOT/linux/lite/manifests/lite-lxqt-packages.list"
    default_provision="linux/lite/scripts/provision-nexus-lite-lxqt.sh"
    default_base_iso="linuxmint-22.3-xfce-64bit.iso"
    default_work="work-lite-lxqt"
    ;;
  *)
    printf 'Unsupported --edition: %s (expected cinnamon, standard, xfce, lite, or lite-lxqt)\n' "$EDITION" >&2
    exit 2
    ;;
esac

SYSTEM_CONF="${NEXUS_SYSTEM_CONF:-$default_conf}"
PKG_MANIFEST="${NEXUS_PKG_MANIFEST:-$default_manifest}"
PROVISION_SCRIPT="${NEXUS_PROVISION_SCRIPT:-$default_provision}"
DOWNLOAD_DIR="${NEXUS_DOWNLOAD_DIR:-$REPO_ROOT/build/downloads}"
BASE_ISO="${NEXUS_BASE_ISO:-$DOWNLOAD_DIR/$default_base_iso}"
MANIFEST_FILE="${NEXUS_BASE_MANIFEST:-$DOWNLOAD_DIR/sha256sum.txt}"
WORK_DIR="${NEXUS_ISO_WORK_DIR:-$REPO_ROOT/build/iso/$default_work}"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"

[[ -r "$SYSTEM_CONF" ]] || { printf 'Missing system config: %s\n' "$SYSTEM_CONF" >&2; exit 1; }
[[ -r "$PKG_MANIFEST" ]] || { printf 'Missing package manifest: %s\n' "$PKG_MANIFEST" >&2; exit 1; }
bash "$VALIDATE_PKGS" "$PKG_MANIFEST" >/dev/null

if [[ "$CHECK_ONLY" == true ]]; then
  exec bash "$PREREQ_SCRIPT" --edition "$EDITION"
fi

conf_version="22.3"
conf_edition="$EDITION"
conf_base_edition=""
conf_arch="x86_64"
while IFS='=' read -r key val; do
  case "$key" in
    NEXUS_BASE_VERSION) conf_version="$val" ;;
    NEXUS_BASE_EDITION) conf_base_edition="$val" ;;
    NEXUS_EDITION) [[ "$EDITION_SET" == false ]] && conf_edition="$val" ;;
    NEXUS_TARGET_ARCH) conf_arch="$val" ;;
  esac
done < "$SYSTEM_CONF"

if [[ -n "$conf_base_edition" && "$conf_edition" != "lite" && "$conf_edition" != "lite-lxqt" ]]; then
  out_slug="$conf_base_edition"
else
  out_slug="$conf_edition"
fi

iso_arch="amd64"
if [[ "$conf_arch" != "x86_64" ]]; then
  iso_arch="$conf_arch"
fi
OUT_ISO="$OUT_DIR/nexus-os-${conf_version}-${out_slug}-${iso_arch}.iso"
BUILD_INFO_PATH="${OUT_ISO}.build-info.json"

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
  echo "NEXUS OS ISO Build Plan (dry-run, edition=$out_slug)"
  echo "  Config: $SYSTEM_CONF"
  echo "  Package manifest: $PKG_MANIFEST"
  echo "  Base ISO: $BASE_ISO"
  echo "  Checksum manifest: $MANIFEST_FILE"
  echo "  Work dir: $WORK_DIR"
  echo "  Output ISO: $OUT_ISO"
  echo "  Build info: $BUILD_INFO_PATH"
  echo "  Packages (${#packages[@]}): ${packages[*]}"
  echo "Step 1: bash $PREREQ_SCRIPT --edition $out_slug --strict"
  echo "Step 2: Verify $BASE_ISO SHA-256 against $MANIFEST_FILE"
  echo "Step 3: Extract ISO tree via xorriso into $WORK_DIR/iso-root and unpack casper/filesystem.squashfs via unsquashfs"
  echo "Step 4: Stage linux/, LICENSE, docs/, index.html, app.js, styles.css, apps/, assets/ and mount dev/proc/sys in $WORK_DIR/squashfs-root, run $PROVISION_SCRIPT, and apply $out_slug branding"
  echo "Step 5: Repack casper/filesystem.squashfs via mksquashfs -comp xz and update casper/filesystem.size + md5sum.txt"
  echo "Step 6: Repack hybrid BIOS+UEFI ISO with xorriso to $OUT_ISO and generate .sha256 + $BUILD_INFO_PATH"
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo 'ISO building requires root privileges for squashfs/chroot operations. Use --dry-run or --check for unprivileged inspection.' >&2
  exit 1
fi

NEXUS_BASE_ISO="$BASE_ISO" bash "$PREREQ_SCRIPT" --edition "$out_slug" --strict
[[ -r "$MANIFEST_FILE" ]] || { printf 'Missing signed checksum manifest: %s (run bash scripts/download-linux-mint.sh --edition %s)\n' "$MANIFEST_FILE" "$out_slug" >&2; exit 1; }

iso_basename="${BASE_ISO##*/}"
expected_sha="$(awk -v file="$iso_basename" '$2 == file || $2 == "*" file { print $1; exit }' "$MANIFEST_FILE")"
[[ "$expected_sha" =~ ^[[:xdigit:]]{64}$ ]] || { printf 'No valid SHA-256 entry for %s in %s\n' "$iso_basename" "$MANIFEST_FILE" >&2; exit 1; }
actual_sha="$(sha256sum "$BASE_ISO" | awk '{print $1}')"
if [[ "$expected_sha" != "$actual_sha" ]]; then
  printf 'Base ISO SHA-256 mismatch: expected %s, got %s\n' "$expected_sha" "$actual_sha" >&2
  exit 1
fi

iso_root="$WORK_DIR/iso-root"
squash_root="$WORK_DIR/squashfs-root"
mounted_chroot=false
resolv_backup=""
policy_rc_added=false
CURRENT_STAGE="init"

cleanup() {
  if [[ "$policy_rc_added" == true ]]; then
    rm -f -- "$squash_root/usr/sbin/policy-rc.d" 2>/dev/null || true
    policy_rc_added=false
  fi
  if [[ -n "$resolv_backup" ]]; then
    rm -f -- "$squash_root/etc/resolv.conf" 2>/dev/null || true
    if [[ "$resolv_backup" == "__SYMLINK__:"* ]]; then
      ln -s "${resolv_backup#__SYMLINK__:}" "$squash_root/etc/resolv.conf" 2>/dev/null || true
    elif [[ -f "$resolv_backup" ]]; then
      mv -f -- "$resolv_backup" "$squash_root/etc/resolv.conf" 2>/dev/null || true
    fi
    resolv_backup=""
  fi
  if [[ "$mounted_chroot" == true ]]; then
    umount -lf "$squash_root/dev/pts" 2>/dev/null || true
    umount -lf "$squash_root/dev" 2>/dev/null || true
    umount -lf "$squash_root/proc" 2>/dev/null || true
    umount -lf "$squash_root/sys" 2>/dev/null || true
    umount -lf "$squash_root/run" 2>/dev/null || true
  fi
}

on_error() {
  local rc=$?
  local failed_cmd="${BASH_COMMAND:-unknown}"
  local iso_exists="false"
  local iso_size="0"
  if [[ -f "$OUT_ISO" ]]; then
    iso_exists="true"
    iso_size="$(stat -c %s "$OUT_ISO" 2>/dev/null || echo 0)"
  fi
  printf 'BUILD STAGE FAILED: stage=%s edition=%s exit=%s out_iso=%s iso_exists=%s iso_size=%s cmd=%s\n' \
    "$CURRENT_STAGE" "$out_slug" "$rc" "$OUT_ISO" "$iso_exists" "$iso_size" "$failed_cmd" >&2
}

trap on_error ERR
trap cleanup EXIT

CURRENT_STAGE="clean-work-dir"
rm -rf -- "$iso_root" "$squash_root"
mkdir -p -- "$iso_root" "$OUT_DIR"

CURRENT_STAGE="extract-base-iso"
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$iso_root"
chmod -R u+w "$iso_root"
CURRENT_STAGE="unsquashfs"
unsquashfs -d "$squash_root" "$iso_root/casper/filesystem.squashfs"

CURRENT_STAGE="mount-chroot"
mount --bind /dev "$squash_root/dev"
mount --bind /dev/pts "$squash_root/dev/pts"
mount -t proc proc "$squash_root/proc"
mount -t sysfs sysfs "$squash_root/sys"
mount --bind /run "$squash_root/run"
mounted_chroot=true

if [[ -L "$squash_root/etc/resolv.conf" ]]; then
  resolv_backup="__SYMLINK__:$(readlink "$squash_root/etc/resolv.conf")"
  rm -f -- "$squash_root/etc/resolv.conf"
elif [[ -f "$squash_root/etc/resolv.conf" ]]; then
  resolv_backup="$WORK_DIR/resolv.conf.orig"
  cp -a "$squash_root/etc/resolv.conf" "$resolv_backup"
fi
if [[ -r /etc/resolv.conf ]]; then
  cp -L /etc/resolv.conf "$squash_root/etc/resolv.conf"
fi
if [[ ! -e "$squash_root/usr/sbin/policy-rc.d" ]]; then
  printf '#!/bin/sh\nexit 101\n' > "$squash_root/usr/sbin/policy-rc.d"
  chmod 0755 "$squash_root/usr/sbin/policy-rc.d"
  policy_rc_added=true
fi

CURRENT_STAGE="stage-chroot-repo"
for req_entry in linux LICENSE docs index.html app.js styles.css apps assets; do
  [[ -e "$REPO_ROOT/$req_entry" ]] || {
    printf 'Missing required repository artifact for chroot staging: %s\n' "$REPO_ROOT/$req_entry" >&2
    exit 1
  }
done
mkdir -p -- "$squash_root/tmp/nexus-repo"
cp -a "$REPO_ROOT/linux" "$squash_root/tmp/nexus-repo/linux"
cp -a "$REPO_ROOT/LICENSE" "$squash_root/tmp/nexus-repo/LICENSE"
cp -a "$REPO_ROOT/docs" "$squash_root/tmp/nexus-repo/docs"
cp -a "$REPO_ROOT/index.html" "$squash_root/tmp/nexus-repo/index.html"
cp -a "$REPO_ROOT/app.js" "$squash_root/tmp/nexus-repo/app.js"
cp -a "$REPO_ROOT/styles.css" "$squash_root/tmp/nexus-repo/styles.css"
cp -a "$REPO_ROOT/apps" "$squash_root/tmp/nexus-repo/apps"
cp -a "$REPO_ROOT/assets" "$squash_root/tmp/nexus-repo/assets"

chroot_env=(PATH=/usr/sbin:/usr/bin:/sbin:/bin)
chroot_args=(--skip-ufw --force)
if [[ "$PROVISION_SCRIPT" == *"provision-nexus-guest.sh" ]]; then
  chroot_args=(--skip-ufw --autostart-firstboot --force)
  [[ "$WITH_GAMING" == true ]] && chroot_args+=(--with-gaming)
  [[ "$WITH_DEV" == true ]] && chroot_args+=(--with-dev)
  chroot_env+=(
    "NEXUS_SYSTEM_CONF=/tmp/nexus-repo/linux/config/${SYSTEM_CONF##*/}"
    "NEXUS_PKG_MANIFEST=/tmp/nexus-repo/linux/config/${PKG_MANIFEST##*/}"
  )
elif [[ "$PROVISION_SCRIPT" == *"provision-nexus-lite.sh" || "$PROVISION_SCRIPT" == *"provision-nexus-lite-lxqt.sh" ]]; then
  chroot_args=(--skip-ufw --purge-bloat --force)
fi

CURRENT_STAGE="chroot-provision"
chroot "$squash_root" /usr/bin/env -i "${chroot_env[@]}" \
  bash "/tmp/nexus-repo/${PROVISION_SCRIPT}" "${chroot_args[@]}"
CURRENT_STAGE="chroot-apt-clean"
chroot "$squash_root" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
  apt-get clean
rm -rf -- "$squash_root/tmp/nexus-repo"

CURRENT_STAGE="unmount-chroot"
cleanup
mounted_chroot=false

CURRENT_STAGE="apply-iso-branding"
bash "$BRANDING_SCRIPT" --iso-root "$iso_root" --squash-root "$squash_root" --edition "$out_slug"

CURRENT_STAGE="mksquashfs"
rm -f -- "$iso_root/casper/filesystem.squashfs"
mksquashfs "$squash_root" "$iso_root/casper/filesystem.squashfs" -comp xz -noappend
printf '%s\n' "$(du -sx --block-size=1 "$squash_root" | awk '{print $1}')" > "$iso_root/casper/filesystem.size"

CURRENT_STAGE="md5sum-manifest"
(
  cd "$iso_root"
  rm -f md5sum.txt
  find . -type f ! -path './isolinux/*' ! -path './boot/grub/*' -print0 | xargs -0 md5sum > md5sum.txt
)

efi_img=""
for cand in "boot/grub/efi.img" "efi.img"; do
  if [[ -f "$iso_root/$cand" ]]; then
    efi_img="$cand"
    break
  fi
done

mkisofs_args=(
  -iso-level 3
  -full-iso9660-filenames
  -volid "NEXUS_${out_slug^^}_${conf_version}"
)
if [[ -f "$iso_root/isolinux/isolinux.bin" ]]; then
  mkisofs_args+=(
    -eltorito-boot isolinux/isolinux.bin
    -eltorito-catalog isolinux/boot.cat
    -no-emul-boot -boot-load-size 4 -boot-info-table
  )
elif [[ -f "$iso_root/boot/grub/i386-pc/eltorito.img" ]]; then
  mkisofs_args+=(
    -eltorito-boot boot/grub/i386-pc/eltorito.img
    -no-emul-boot -boot-load-size 4 -boot-info-table
  )
fi
if [[ -n "$efi_img" ]]; then
  mkisofs_args+=(
    -eltorito-alt-boot
    -e "$efi_img"
    -no-emul-boot
    -isohybrid-gpt-basdat
  )
fi

CURRENT_STAGE="xorriso-mkisofs"
xorriso -as mkisofs "${mkisofs_args[@]}" -output "$OUT_ISO" "$iso_root"

CURRENT_STAGE="sha256sum"
(
  cd "$OUT_DIR"
  sha256sum "${OUT_ISO##*/}" > "${OUT_ISO##*/}.sha256"
)

CURRENT_STAGE="build-info"

built_sha="$(awk '{print $1}' "${OUT_ISO}.sha256")"
git_commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo 'unknown')"
git_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
git_dirty="false"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true)" ]]; then
  git_dirty="true"
fi
xorriso_ver="$(xorriso -version 2>/dev/null | head -n1 | tr -d '"' || echo 'unknown')"
mksquashfs_ver="$(mksquashfs -version 2>/dev/null | head -n1 | tr -d '"' || echo 'unknown')"
host_os="$(uname -sr 2>/dev/null | tr -d '"' || echo 'unknown')"
host_arch="$(uname -m 2>/dev/null | tr -d '"' || echo 'unknown')"
cat > "$BUILD_INFO_PATH" <<JSON
{
  "name": "NEXUS OS",
  "base_distro": "linuxmint",
  "base_version": "${conf_version}",
  "ubuntu_codename": "noble",
  "edition": "${out_slug}",
  "arch": "${iso_arch}",
  "base_iso": "${iso_basename}",
  "base_iso_sha256": "${actual_sha}",
  "output_iso": "${OUT_ISO##*/}",
  "output_iso_sha256": "${built_sha}",
  "checksum_file": "${OUT_ISO##*/}.sha256",
  "source_commit": "${git_commit}",
  "source_branch": "${git_branch}",
  "source_dirty": ${git_dirty},
  "package_repositories": [
    "Ubuntu 24.04 Noble (signed APT)",
    "Linux Mint 22.3 Zena (signed APT)"
  ],
  "build_environment": {
    "host_os": "${host_os}",
    "host_arch": "${host_arch}",
    "xorriso": "${xorriso_ver}",
    "mksquashfs": "${mksquashfs_ver}"
  },
  "with_gaming": ${WITH_GAMING},
  "with_dev": ${WITH_DEV},
  "built_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
cp -f -- "$BUILD_INFO_PATH" "$OUT_DIR/build-info.json"

printf 'Built NEXUS OS ISO: %s\n' "$OUT_ISO"
