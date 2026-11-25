#!/usr/bin/env bash
# Apply non-invasive NEXUS OS branding to an extracted Linux Mint ISO tree and
# squashfs root while preserving Mint's /etc/os-release and legal notices.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

ISO_ROOT=""
SQUASH_ROOT=""
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/build/apply-iso-branding.sh --iso-root PATH --squash-root PATH [OPTIONS]

Applies NEXUS OS boot menu labels, live desktop installer shortcut, Cinnamon/Xfce
theme assets, and legal/recovery documentation into an unpacked ISO staging tree.

Options:
  --iso-root PATH      Extracted ISO root directory
  --squash-root PATH   Unpacked squashfs root directory
  --dry-run            Print branding actions without modifying files
  --help, -h           Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --iso-root) [[ $# -ge 2 ]] || { echo '--iso-root requires a path' >&2; exit 2; }; ISO_ROOT="$2"; shift 2 ;;
    --squash-root) [[ $# -ge 2 ]] || { echo '--squash-root requires a path' >&2; exit 2; }; SQUASH_ROOT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Update GRUB/ISOLINUX menu titles in ${ISO_ROOT:-<iso-root>} (preserving Linux Mint legal notices)"
  echo "[dry-run] Install Cinnamon/Xfce theme assets, LICENSE, and docs into ${SQUASH_ROOT:-<squash-root>}/usr/local/share/nexus-os/"
  echo "[dry-run] Stage Install NEXUS OS shortcut in ${SQUASH_ROOT:-<squash-root>}/etc/skel/Desktop/nexus-installer.desktop"
  exit 0
fi

[[ -d "$ISO_ROOT" && -d "$SQUASH_ROOT" ]] || { echo 'Both --iso-root and --squash-root must be existing directories.' >&2; exit 2; }

for cfg in "$ISO_ROOT/boot/grub/grub.cfg" "$ISO_ROOT/isolinux/txt.cfg" "$ISO_ROOT/isolinux/isolinux.cfg"; do
  if [[ -w "$cfg" ]]; then
    sed -i 's/Start Linux Mint/Start NEXUS OS (Linux Mint)/g' "$cfg" || true
  fi
done

install -d -m 0755 "$SQUASH_ROOT/usr/local/share/nexus-os/cinnamon" "$SQUASH_ROOT/usr/local/share/nexus-os/docs"
cp -a "$REPO_ROOT/linux/cinnamon/." "$SQUASH_ROOT/usr/local/share/nexus-os/cinnamon/"
install -m 0644 "$REPO_ROOT/LICENSE" "$SQUASH_ROOT/usr/local/share/nexus-os/LICENSE"
install -m 0644 "$REPO_ROOT/docs/RECOVERY_AND_BOOT.md" "$SQUASH_ROOT/usr/local/share/nexus-os/docs/RECOVERY_AND_BOOT.md"

install -d -m 0755 "$SQUASH_ROOT/etc/skel/Desktop"
install -m 0755 "$REPO_ROOT/linux/branding/applications/nexus-installer.desktop" "$SQUASH_ROOT/etc/skel/Desktop/nexus-installer.desktop"

echo "Applied NEXUS ISO branding into $ISO_ROOT and $SQUASH_ROOT"
