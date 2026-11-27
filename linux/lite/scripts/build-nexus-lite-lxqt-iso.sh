#!/usr/bin/env bash
# Reproducible NEXUS Lite LXQt Candidate live-ISO builder.
# Keeps build output & work directory isolated from the Openbox Lite ISO.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
VALIDATE_PKGS="$REPO_ROOT/linux/build/validate-packages.sh"
LXQT_MANIFEST="$REPO_ROOT/linux/lite/manifests/lite-lxqt-packages.list"
LXQT_CONF="$REPO_ROOT/linux/lite/nexus-lite-lxqt.conf"
WORK_DIR="${NEXUS_ISO_WORK_DIR:-$REPO_ROOT/build/iso/work-lite-lxqt}"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"
OUT_ISO="$OUT_DIR/nexus-os-22.3-lite-lxqt-amd64.iso"

DRY_RUN=false
CHECK_ONLY=false

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/lite/scripts/build-nexus-lite-lxqt-iso.sh [OPTIONS]

Prepares and builds the isolated NEXUS Lite LXQt candidate ISO
(Ubuntu/Lubuntu LXQt + Openbox + PCManFM-Qt + QTerminal + ZRAM)
without touching the existing Openbox Lite ISO.

Options:
  --check     Validate LXQt manifest and host ISO build prerequisites
  --dry-run   Print LXQt ISO build plan without root or ISO tools
  --help, -h  Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

bash "$VALIDATE_PKGS" "$LXQT_MANIFEST" >/dev/null

if [[ "$CHECK_ONLY" == true ]]; then
  exec bash "$REPO_ROOT/linux/build/check-build-prereqs.sh" --edition lite-lxqt
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "NEXUS Lite LXQt Candidate ISO Build Plan (dry-run)"
  echo "  Manifest: $LXQT_MANIFEST"
  echo "  Desktop: LXQt + Openbox WM (PCManFM-Qt, QTerminal, FeatherPad, Qps, ZRAM)"
  echo "  Work dir: $WORK_DIR"
  echo "  Output ISO: $OUT_ISO"
  echo "  Provisioner: linux/lite/scripts/provision-nexus-lite-lxqt.sh --skip-ufw --purge-bloat --force"
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo 'NEXUS Lite LXQt ISO building requires root privileges. Use --dry-run or --check.' >&2
  exit 1
fi

bash "$REPO_ROOT/linux/build/check-build-prereqs.sh" --edition lite-lxqt --strict
NEXUS_EDITION="lite-lxqt" \
NEXUS_SYSTEM_CONF="$LXQT_CONF" \
NEXUS_PKG_MANIFEST="$LXQT_MANIFEST" \
NEXUS_PROVISION_SCRIPT="linux/lite/scripts/provision-nexus-lite-lxqt.sh" \
NEXUS_ISO_WORK_DIR="$WORK_DIR" \
  exec bash "$REPO_ROOT/linux/build/build-nexus-iso.sh" --edition lite-lxqt
