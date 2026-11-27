#!/usr/bin/env bash
# Low-memory installation preflight and CLI installer wrapper for NEXUS Lite
# (supports both Openbox `lite` and LXQt `lite-lxqt` editions without overriding
# the active edition).
# For >= 1024 MiB RAM, Ubiquity GTK is supported; for 512–768 MiB RAM, delegates
# to nexus-disk-install.sh (CLI partition + copy + GRUB install).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
DISK_INSTALL="$SCRIPT_DIR/../installer/nexus-disk-install.sh"
[[ -x "$DISK_INSTALL" ]] || DISK_INSTALL="$(command -v nexus-disk-install || true)"

detect_lite_edition() {
  local rel="/etc/nexus-os-release"
  local ed=""
  if [[ -r "$rel" ]]; then
    ed="$(awk -F= '/^NEXUS_EDITION=/{gsub(/["'"'"']/, "", $2); print tolower($2)}' "$rel" 2>/dev/null || true)"
  fi
  case "$ed" in
    lite|lite-lxqt) printf '%s\n' "$ed" ;;
    *) printf 'lite\n' ;;
  esac
}

DRY_RUN=false
HAS_DISK=false
EXPLICIT_EDITION=""
PASSTHROUGH=()
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; PASSTHROUGH+=("$1"); shift ;;
    --disk)
      HAS_DISK=true
      PASSTHROUGH+=("$1")
      if [[ $# -ge 2 ]]; then
        PASSTHROUGH+=("$2")
        shift 2
      else
        shift
      fi
      ;;
    --edition)
      [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }
      EXPLICIT_EDITION="$2"
      PASSTHROUGH+=("$1" "$2")
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: bash linux/lite/nexus-lite-install.sh [OPTIONS]

Low-memory preflight and CLI installer wrapper for NEXUS Lite (Openbox or LXQt).
Detects active edition from /etc/nexus-os-release unless --edition is passed.

Options:
  --dry-run          Preview installation steps without modifying disks
  --edition NAME     Explicitly choose lite | lite-lxqt
  --disk DEV ...     Forward installation flags directly to nexus-disk-install
  --help, -h         Show this help message
USAGE
      exit 0 ;;
    *) PASSTHROUGH+=("$1"); shift ;;
  esac
done

ACTIVE_EDITION="${EXPLICIT_EDITION:-$(detect_lite_edition)}"
ram_mib="$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
echo "NEXUS Lite Low-Memory Installer Preflight (Edition: ${ACTIVE_EDITION} | Detected RAM: ${ram_mib} MiB)"

if (( ram_mib < 512 )); then
  echo "ERROR: Detected RAM (${ram_mib} MiB) is below the 512 MiB experimental minimum for NEXUS Lite." >&2
  exit 1
fi

if (( ram_mib < 1024 )); then
  echo "WARNING: Graphical Ubiquity requires >= 1024 MiB RAM and may stall below 850 MiB."
  if [[ "$ACTIVE_EDITION" == "lite-lxqt" ]]; then
    echo "NOTE: NEXUS Lite LXQt targets >= 1024 MiB RAM; 512-768 MiB is tuned for NEXUS Lite (Openbox)."
  fi
  echo "Using NEXUS Lite CLI disk installer path (nexus-disk-install) with zram active."
fi

if [[ "$DRY_RUN" == true && "$HAS_DISK" == false ]]; then
  echo "[dry-run] Active edition=${ACTIVE_EDITION}"
  echo '[dry-run] Check swap/zram -> verify target block device explicitly -> run Ubiquity (>= 1 GiB) or nexus-disk-install --disk /dev/sdX'
  exit 0
fi

if [[ -n "$DISK_INSTALL" && -x "$DISK_INSTALL" && "$HAS_DISK" == true ]]; then
  if [[ -n "$EXPLICIT_EDITION" ]]; then
    exec bash "$DISK_INSTALL" "${PASSTHROUGH[@]}"
  else
    exec bash "$DISK_INSTALL" --edition "$ACTIVE_EDITION" "${PASSTHROUGH[@]}"
  fi
fi

bash "$SCRIPT_DIR/configure-zram.sh" status
echo "Pass --disk /dev/sdX --user <name> --yes-erase-disk (or --dry-run) to install via CLI, or use nexus-installer-launcher --launch (>= 1 GiB)."
