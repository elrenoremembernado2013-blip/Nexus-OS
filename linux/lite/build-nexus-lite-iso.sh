#!/usr/bin/env bash
# Reproducible NEXUS Lite live-ISO builder (based on Linux Mint 22.3 ISO).
# Keeps the standard NEXUS ISO build separate and writes nexus-os-22.3-lite-amd64.iso.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_PKGS="$REPO_ROOT/linux/build/validate-packages.sh"
LITE_MANIFEST="$SCRIPT_DIR/lite-packages.list"
OUT_DIR="${NEXUS_ISO_OUT_DIR:-$REPO_ROOT/build/iso/out}"
OUT_ISO="$OUT_DIR/nexus-os-22.3-lite-amd64.iso"

DRY_RUN=false
CHECK_ONLY=false

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/lite/build-nexus-lite-iso.sh [OPTIONS]

Prepares and builds the ultra-low-RAM NEXUS Lite ISO (Openbox + tint2, no
Cinnamon/Steam/default browser) from a GPG/SHA-256 verified Linux Mint base ISO.

Options:
  --check     Validate Lite manifest and host ISO build prerequisites
  --dry-run   Print Lite ISO build plan without root or ISO tools
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

bash "$VALIDATE_PKGS" "$LITE_MANIFEST" >/dev/null

if [[ "$CHECK_ONLY" == true ]]; then
  exec bash "$REPO_ROOT/linux/build/check-build-prereqs.sh"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "NEXUS Lite ISO Build Plan (dry-run)"
  echo "  Manifest: $LITE_MANIFEST"
  echo "  Desktop: Openbox + tint2 (no Cinnamon, no compositor, no Steam/default browser)"
  echo "  Output ISO: $OUT_ISO"
  echo "  Provisioner: linux/lite/provision-nexus-lite.sh --force"
  echo "  Note: 512 MB profile is marked EXPERIMENTAL pending VM acceptance tests."
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo 'NEXUS Lite ISO building requires root privileges. Use --dry-run or --check.' >&2
  exit 1
fi

bash "$REPO_ROOT/linux/build/check-build-prereqs.sh" --strict
NEXUS_SYSTEM_CONF="$SCRIPT_DIR/nexus-lite.conf" \
NEXUS_PKG_MANIFEST="$LITE_MANIFEST" \
NEXUS_PROVISION_SCRIPT="linux/lite/provision-nexus-lite.sh" \
  exec bash "$REPO_ROOT/linux/build/build-nexus-iso.sh"
