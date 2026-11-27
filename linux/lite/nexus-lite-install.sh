#!/usr/bin/env bash
# Low-memory installation preflight and CLI installer wrapper for NEXUS Lite.
# For >= 1024 MiB RAM, Ubiquity GTK is supported; for 512–768 MiB RAM, delegates
# to nexus-disk-install.sh (CLI partition + copy + GRUB install).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
DISK_INSTALL="$SCRIPT_DIR/../installer/nexus-disk-install.sh"
[[ -x "$DISK_INSTALL" ]] || DISK_INSTALL="$(command -v nexus-disk-install || true)"

DRY_RUN=false
PASSTHROUGH=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; PASSTHROUGH+=("$1"); shift ;;
    --help|-h)
      echo "Usage: bash linux/lite/nexus-lite-install.sh [--dry-run] [--disk /dev/sdX --yes-erase-disk ...]"
      exit 0 ;;
    *) PASSTHROUGH+=("$1"); shift ;;
  esac
done

ram_mib="$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
echo "NEXUS Lite Low-Memory Installer Preflight (Detected RAM: ${ram_mib} MiB)"

if (( ram_mib < 1024 )); then
  echo "WARNING: Graphical Ubiquity typically requires >= 1024 MiB RAM and may stall at 512 MiB."
  echo "Using NEXUS Lite CLI disk installer path (nexus-disk-install) with zram active."
fi

if [[ "$DRY_RUN" == true && ${#PASSTHROUGH[@]} -eq 1 ]]; then
  echo '[dry-run] Check swap/zram -> verify target block device explicitly -> run Ubiquity (>= 1 GiB) or nexus-disk-install --disk /dev/sdX'
  exit 0
fi

if [[ -n "$DISK_INSTALL" && -x "$DISK_INSTALL" && ${#PASSTHROUGH[@]} -gt 0 ]]; then
  exec bash "$DISK_INSTALL" --edition lite "${PASSTHROUGH[@]}"
fi

bash "$SCRIPT_DIR/configure-zram.sh" status
echo 'Pass --disk /dev/sdX --user <name> --yes-erase-disk (or --dry-run) to install via CLI, or use nexus-installer-launcher --launch (>= 1 GiB).'
