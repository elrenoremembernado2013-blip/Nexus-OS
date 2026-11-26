#!/usr/bin/env bash
# Validate a built NEXUS OS ISO image, its SHA-256 checksum, boot catalog,
# Casper live filesystem layout, and edition-specific build-info.json metadata.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"
EDITION=""
ISO_PATH=""
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/build/verify-nexus-iso.sh [OPTIONS] [ISO_PATH]

Verifies an output NEXUS OS ISO file, SHA-256 manifest, build-info.json, and
boot/casper filesystem entries via xorriso.

Options:
  --edition NAME  cinnamon | standard | xfce | lite (selects default ISO path)
  --dry-run       Validate script paths and print planned verification steps
  --help, -h      Show this help message
USAGE
}

args=()
while (($#)); do
  case "$1" in
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done

if ((${#args[@]} > 0)); then
  ISO_PATH="${args[0]}"
else
  case "$EDITION" in
    cinnamon|standard) ISO_PATH="$OUT_DIR/nexus-os-22.3-cinnamon-amd64.iso" ;;
    lite) ISO_PATH="$OUT_DIR/nexus-os-22.3-lite-amd64.iso" ;;
    lite-lxqt) ISO_PATH="$OUT_DIR/nexus-os-22.3-lite-lxqt-amd64.iso" ;;
    ""|xfce) ISO_PATH="$OUT_DIR/nexus-os-22.3-xfce-amd64.iso" ;;
    *) printf 'Unsupported --edition: %s\n' "$EDITION" >&2; exit 2 ;;
  esac
fi

info_file="${ISO_PATH}.build-info.json"
if [[ ! -r "$info_file" ]]; then
  info_file="$(dirname "$ISO_PATH")/build-info.json"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "NEXUS ISO Verification Plan (dry-run)"
  echo "  Target ISO: $ISO_PATH"
  echo "  Check 1: Verify ISO exists and size >= 500 MiB"
  echo "  Check 2: Verify SHA-256 checksum against ${ISO_PATH}.sha256"
  echo "  Check 3: Validate ${info_file} schema"
  echo "  Check 4: Inspect boot catalog (isolinux.bin, efi.img) and casper/filesystem.squashfs via xorriso"
  exit 0
fi

[[ -r "$ISO_PATH" ]] || { printf 'ISO file not found: %s\n' "$ISO_PATH" >&2; exit 1; }
[[ -r "${ISO_PATH}.sha256" ]] || { printf 'Missing checksum file: %s.sha256\n' "$ISO_PATH" >&2; exit 1; }

size_bytes="$(stat -c %s "$ISO_PATH")"
(( size_bytes >= 524288000 )) || { printf 'ISO unexpectedly small (%s bytes)\n' "$size_bytes" >&2; exit 1; }

(
  cd "$(dirname "$ISO_PATH")"
  sha256sum -c "$(basename "${ISO_PATH}.sha256")"
)

[[ -r "$info_file" ]] || { printf 'Missing build metadata: %s\n' "$info_file" >&2; exit 1; }
python3 - "$info_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for key in ("name", "base_distro", "base_version", "edition", "arch", "output_iso", "output_iso_sha256"):
    assert data.get(key), f"Missing {key} in build-info.json"
PY

if command -v xorriso >/dev/null 2>&1; then
  listing="$(xorriso -indev "$ISO_PATH" -find / -maxdepth 4 2>/dev/null || true)"
  for required in "/casper/filesystem.squashfs" "/casper/vmlinuz"; do
    printf '%s\n' "$listing" | grep -Fq "$required" || {
      printf 'Missing required live/boot entry in ISO: %s\n' "$required" >&2
      exit 1
    }
  done
  if ! printf '%s\n' "$listing" | grep -Eq '/boot/grub/efi\.img|/efi\.img|/EFI/boot/bootx64\.efi'; then
    echo 'Missing UEFI boot image (/boot/grub/efi.img or /EFI/boot/bootx64.efi) in ISO' >&2
    exit 1
  fi
  if ! printf '%s\n' "$listing" | grep -Eq '/isolinux/isolinux\.bin|/boot/grub/i386-pc/eltorito\.img'; then
    echo 'Missing BIOS El Torito boot image in ISO' >&2
    exit 1
  fi
  echo "PASS ISO structure and boot entries verified via xorriso."

  # Production/test separation verification: ensure zero test agents/hooks exist in released ISO
  sep_tmp="$(mktemp -d "${TMPDIR:-/tmp}/nexus-iso-sep.XXXXXX")"
  trap 'rm -rf -- "$sep_tmp"' EXIT
  initrd_entry="$(printf '%s\n' "$listing" | tr -d "'" | grep -E '/casper/initrd(\.lz|\.gz|\.xz)?$' | head -n1 || true)"
  if [[ -n "$initrd_entry" && -x "$(command -v unmkinitramfs || true)" ]]; then
    xorriso -osirrox on -indev "$ISO_PATH" -extract "$initrd_entry" "$sep_tmp/initrd" >/dev/null 2>&1
    mkdir -p -- "$sep_tmp/initrd-tree"
    unmkinitramfs "$sep_tmp/initrd" "$sep_tmp/initrd-tree"
    if find "$sep_tmp/initrd-tree" \( -name '*nexus-test*' -o -name '*casper-test*' -o -name '*99nexus_test_harness*' -o -name '*nexus-guest-test*' \) | grep -q .; then
      echo 'SECURITY FAIL: Test harness artifact found inside released ISO initramfs!' >&2
      exit 1
    fi
    if grep -rnq 'org\.nexus\.test\.0' "$sep_tmp/initrd-tree" 2>/dev/null; then
      echo 'SECURITY FAIL: Test virtio-serial channel reference found inside released ISO initramfs!' >&2
      exit 1
    fi
    echo 'PASS production/test separation: zero test hooks in released ISO initramfs.'
  fi
  if command -v unsquashfs >/dev/null 2>&1; then
    xorriso -osirrox on -indev "$ISO_PATH" -extract /casper/filesystem.squashfs "$sep_tmp/fs.squashfs" >/dev/null 2>&1
    sq_list="$(unsquashfs -l "$sep_tmp/fs.squashfs" 2>/dev/null || true)"
    if printf '%s\n' "$sq_list" | grep -Eq 'nexus-test-agent|nexus-guest-test|casper-test-hook|99nexus_test_harness|/libexec/nexus-test'; then
      echo 'SECURITY FAIL: Test agent/script found inside released ISO filesystem.squashfs!' >&2
      exit 1
    fi
    echo 'PASS production/test separation: zero test agents in released ISO squashfs.'
  fi
  rm -rf -- "$sep_tmp"
  trap - EXIT
else
  echo 'WARN xorriso not installed; skipped internal ISO tree inspection.' >&2
fi

printf 'PASS verified NEXUS OS ISO (%s bytes): %s\n' "$size_bytes" "$ISO_PATH"
