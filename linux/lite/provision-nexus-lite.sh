#!/usr/bin/env bash
# Provision a Linux Mint 22.3 (Ubuntu Noble) guest with NEXUS Lite (Openbox + tint2).
# Preserves ufw, unattended-upgrades, APT signature verification, and /etc/os-release.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
MANIFEST="$SCRIPT_DIR/lite-packages.list"

DRY_RUN=false
WITH_BROWSER=false
FORCE=false

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/lite/provision-nexus-lite.sh [OPTIONS]

Provisions a Linux Mint 22.3 (Ubuntu Noble) guest for NEXUS Lite (512 MB
Experimental / 1 GB) using Openbox, tint2, PCManFM, LXTerminal, and zram-tools.

Options:
  --dry-run       Preview provisioning commands without changing the system
  --with-browser  Include optional lightweight browser (falkon)
  --force         Skip OS check
  --help, -h      Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --with-browser) WITH_BROWSER=true; shift ;;
    --force) FORCE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

if [[ "$DRY_RUN" == false && "$(id -u)" -ne 0 ]]; then
  echo 'Run provision-nexus-lite.sh as root (sudo) or pass --dry-run.' >&2
  exit 1
fi

if [[ "$DRY_RUN" == false && "$FORCE" == false && -r /etc/os-release ]]; then
  if ! grep -Eq '^ID=(linuxmint|ubuntu)$' /etc/os-release; then
    echo 'Expected Linux Mint / Ubuntu host; pass --force to override.' >&2
    exit 1
  fi
fi

packages=()
while IFS=':' read -r cat pkg; do
  [[ -z "${cat:-}" || "$cat" == \#* ]] && continue
  pkg="${pkg%%[[:space:]]*}"
  case "$cat" in
    core|desktop|nexus) packages+=("$pkg") ;;
    optional) [[ "$WITH_BROWSER" == true && "$pkg" == "falkon" ]] && packages+=("$pkg") ;;
  esac
done < "$MANIFEST"

run_cmd apt-get update
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
run_cmd install -d -m 0755 /usr/local/share/nexus-os/lite /usr/local/bin
run_cmd install -m 0755 "$SCRIPT_DIR/apply-nexus-lite.sh" /usr/local/bin/nexus-apply-lite
run_cmd install -m 0755 "$SCRIPT_DIR/configure-zram.sh" /usr/local/bin/nexus-configure-zram
run_cmd install -m 0755 "$SCRIPT_DIR/memory-audit.sh" /usr/local/bin/nexus-memory-audit
run_cmd cp -a "$SCRIPT_DIR/openbox" /usr/local/share/nexus-os/lite/

if [[ "$DRY_RUN" == true ]]; then
  echo '[dry-run] Configure UFW default deny incoming + zram swap + /etc/nexus-os-release (NEXUS_EDITION=lite)'
else
  bash "$SCRIPT_DIR/configure-zram.sh" enable
  if command -v ufw >/dev/null 2>&1; then
    ufw default deny incoming || true
    ufw default allow outgoing || true
    ufw --force enable || true
  fi
  cat > /etc/nexus-os-release <<'META'
NEXUS_NAME="NEXUS OS Lite"
NEXUS_EDITION="lite"
NEXUS_BASE_DISTRO="linuxmint"
NEXUS_BASE_CODENAME="noble"
NEXUS_DESKTOP="openbox"
META
  chmod 0644 /etc/nexus-os-release
fi

echo 'NEXUS Lite provisioning complete.'
