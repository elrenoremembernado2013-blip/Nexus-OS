#!/usr/bin/env bash
# Low-memory installation preflight and honest guidance for NEXUS Lite.
# Warns clearly if RAM < 1024 MiB because graphical Ubiquity typically needs >= 1 GiB.
set -euo pipefail

DRY_RUN=false
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: bash linux/lite/nexus-lite-install.sh [--dry-run]"
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

ram_mib="$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
echo "NEXUS Lite Low-Memory Installer Preflight (Detected RAM: ${ram_mib} MiB)"

if (( ram_mib < 1024 )); then
  echo "WARNING: Graphical Ubiquity typically requires >= 1024 MiB RAM and may fail or stall at 512 MiB."
  echo "Recommended low-memory path: boot to console/Openbox with zram active or install via debootstrap/CLI chroot on a target disk."
fi

if [[ "$DRY_RUN" == true ]]; then
  echo '[dry-run] Check swap/zram -> verify target block device explicitly -> run Ubiquity (>= 1 GiB) or CLI debootstrap install'
  exit 0
fi

bash "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/configure-zram.sh" status
echo 'Run nexus-installer-launcher --launch (if >= 1 GiB RAM) or follow docs/NEXUS_LITE.md for CLI low-RAM setup.'
