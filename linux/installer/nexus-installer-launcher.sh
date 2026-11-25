#!/usr/bin/env bash
# NEXUS OS Live-Session Installer Launcher wrapping Linux Mint's Ubiquity.
# Runs hardware preflight first, logs non-secret diagnostics, never stores or logs
# passwords, and never silently partitions or erases any disk.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/nexus-install-preflight.sh"
[[ -x "$PREFLIGHT" ]] || PREFLIGHT="$(command -v nexus-install-preflight || true)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nexus-os"
LOG_FILE="$LOG_DIR/installer.log"

DRY_RUN=false
CHECK_ONLY=false
CONFIRM_LAUNCH=false

usage() {
  cat <<'USAGE'
Usage: bash linux/installer/nexus-installer-launcher.sh [OPTIONS]

Validates system readiness for installing NEXUS OS via Linux Mint's Ubiquity
installer (supporting Guided erase, Alongside existing OS, Manual partitioning,
and optional LUKS full-disk encryption inside Ubiquity).

Options:
  --check           Run hardware/firmware/Ubiquity preflight and exit
  --launch          Launch Ubiquity installer via pkexec (live Mint session only)
  --dry-run         Print preflight and exact pkexec ubiquity command without running
  --help, -h        Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --launch) CONFIRM_LAUNCH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

bash "$PREFLIGHT" --summary

if [[ "$CHECK_ONLY" == true ]]; then
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] mkdir -p %s\n' "$LOG_DIR"
  echo '[dry-run] pkexec ubiquity --desktop %k gtk_ui'
  echo '[dry-run] User accounts, disk partitioning, and optional LUKS encryption are confirmed interactively inside Ubiquity; no passwords are stored in logs.'
  exit 0
fi

if [[ "$CONFIRM_LAUNCH" == false ]]; then
  echo 'Pass --launch inside a booted NEXUS/Mint live session to start Ubiquity, or --check / --dry-run to inspect safely.' >&2
  exit 2
fi

if ! command -v ubiquity >/dev/null 2>&1; then
  echo 'Ubiquity installer is not installed on this host. Boot a live NEXUS OS / Linux Mint ISO to install.' >&2
  exit 1
fi

if ! command -v pkexec >/dev/null 2>&1; then
  echo 'pkexec is unavailable; cannot elevate safely to launch Ubiquity.' >&2
  exit 1
fi

mkdir -p -- "$LOG_DIR"
printf '[%s] Launching Linux Mint Ubiquity installer (uid=%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(id -u)" >> "$LOG_FILE"
exec pkexec ubiquity gtk_ui
