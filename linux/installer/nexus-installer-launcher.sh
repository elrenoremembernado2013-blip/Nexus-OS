#!/usr/bin/env bash
# NEXUS OS Live-Session Installer Launcher wrapping Linux Mint's Ubiquity.
# Runs hardware preflight first, never silently bypasses serious blockers,
# logs non-secret diagnostics, never stores or logs passwords, and never
# silently partitions or erases any disk.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/nexus-install-preflight.sh"
[[ -x "$PREFLIGHT" ]] || PREFLIGHT="$(command -v nexus-install-preflight || true)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nexus-os"
LOG_FILE="$LOG_DIR/installer.log"

DRY_RUN=false
CHECK_ONLY=false
CONFIRM_LAUNCH=false
FORCE_LOW_RAM=false

usage() {
  cat <<'USAGE'
Usage: bash linux/installer/nexus-installer-launcher.sh [OPTIONS]

Validates system readiness for installing NEXUS OS via Linux Mint's Ubiquity
installer (supporting Guided erase, Alongside existing OS, Manual partitioning,
and optional LUKS full-disk encryption inside Ubiquity).

Options:
  --check           Run hardware/firmware/Ubiquity preflight and exit
  --launch          Launch Ubiquity installer via pkexec (live Mint session only)
  --force-low-ram   Acknowledge low-RAM warning (< 850 MiB) and attempt GUI launch anyway
  --dry-run         Print preflight and exact pkexec ubiquity command without running
  --help, -h        Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --launch) CONFIRM_LAUNCH=true; shift ;;
    --force-low-ram) FORCE_LOW_RAM=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$PREFLIGHT" && -x "$PREFLIGHT" ]] || { echo 'nexus-install-preflight not found.' >&2; exit 1; }

PREFLIGHT_JSON="$(bash "$PREFLIGHT" --json)"
printf '%s\n' "$PREFLIGHT_JSON" | python3 -c '
import json, sys
p = json.load(sys.stdin)
hw = p.get("hardware", {})
sb = p.get("secure_boot_status", {})
db = p.get("dual_boot_detection", {})
arch = p.get("arch")
ed = p.get("edition")
fw = p.get("firmware")
sb_state = sb.get("secure_boot_state")
env_lbl = p.get("environment", {}).get("label", "unknown")
print(f"NEXUS OS Install Preflight ({arch} / edition={ed} / {fw} / SecureBoot={sb_state})")
print(f"  Environment: {env_lbl}")
print("  CPU:", hw.get("cpu"))
print("  RAM:", hw.get("ram_total_mib"), "MiB total (", hw.get("ram_available_mib"), "MiB avail)")
print("  Disks:", len(hw.get("disks", [])), "(>=20GiB:", hw.get("eligible_disks_ge_20gib", 0), ") | ESPs:", len(db.get("esp_partitions", [])), "| NTFS:", len(db.get("ntfs_partitions", [])), "| LUKS:", len(db.get("luks_partitions", [])))
for w in p.get("structured_warnings", []):
    sev = str(w.get("severity", "info")).upper()
    print(f"  [{sev}]", w["problem"], "(can_continue=" + str(w["can_continue"]) + ")")
    print("    Why:", w["why_it_matters"])
    print("    Action:", w["recommended_action"])
'

if [[ "$CHECK_ONLY" == true ]]; then
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] mkdir -p %s\n' "$LOG_DIR"
  echo '[dry-run] Verify preflight has zero hardware blockers and RAM >= 850 MiB (unless --force-low-ram)'
  echo '[dry-run] pkexec ubiquity gtk_ui'
  echo '[dry-run] User accounts, disk partitioning, and optional LUKS encryption are confirmed interactively inside Ubiquity; no passwords are stored in logs.'
  echo '[dry-run] On failure or boot issues, run: nexus-recovery --diagnose'
  exit 0
fi

if [[ "$CONFIRM_LAUNCH" == false ]]; then
  echo 'Pass --launch inside a booted NEXUS/Mint live session to start Ubiquity, or --check / --dry-run to inspect safely.' >&2
  exit 2
fi

notify_gui_warning() {
  local title="$1" msg="$2"
  if [[ ! -t 1 && ! -t 2 && -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    if command -v zenity >/dev/null 2>&1; then
      zenity --warning --title="$title" --text="$msg" >/dev/null 2>&1 || true
    elif command -v yad >/dev/null 2>&1; then
      yad --image=dialog-warning --title="$title" --text="$msg" --button=OK:0 >/dev/null 2>&1 || true
    elif command -v xmessage >/dev/null 2>&1; then
      xmessage -center "$title: $msg" >/dev/null 2>&1 || true
    elif command -v notify-send >/dev/null 2>&1; then
      notify-send -u critical "$title" "$msg" >/dev/null 2>&1 || true
    fi
  fi
}

# Never silently bypass hard hardware blockers
HARD_BLOCKER="$(printf '%s\n' "$PREFLIGHT_JSON" | python3 -c '
import json, sys
p = json.load(sys.stdin)
bs = p.get("blockers", [])
if bs:
    print(bs[0]["problem"] + " " + bs[0]["recommended_action"])
')"
if [[ -n "$HARD_BLOCKER" ]]; then
  echo "INSTALLATION BLOCKED: $HARD_BLOCKER" >&2
  notify_gui_warning "NEXUS OS Installer Blocked" "$HARD_BLOCKER"
  exit 1
fi

RAM_MIB="$(printf '%s\n' "$PREFLIGHT_JSON" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("hardware", {}).get("ram_total_mib") or 0)')"
if (( RAM_MIB > 0 && RAM_MIB < 850 )) && [[ "$FORCE_LOW_RAM" == false ]]; then
  low_ram_msg="Detected ${RAM_MIB} MiB RAM (below 850 MiB safe floor for graphical Ubiquity). Open a terminal and run: sudo nexus-lite-install --disk /dev/sdX --user <name> --yes-erase-disk"
  echo "WARNING: $low_ram_msg" >&2
  echo "Or pass --force-low-ram if you explicitly want to attempt Ubiquity GTK anyway." >&2
  notify_gui_warning "NEXUS OS Low-RAM Installer Guidance" "$low_ram_msg"
  exit 1
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
printf '[%s] Launching Linux Mint Ubiquity installer (uid=%s, ram_mib=%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(id -u)" "$RAM_MIB" >> "$LOG_FILE"
rc=0
pkexec ubiquity gtk_ui || rc=$?
if (( rc != 0 )); then
  printf '[%s] Ubiquity exited non-zero (rc=%s). Inspect /var/log/installer/syslog or run nexus-recovery --diagnose\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rc" >> "$LOG_FILE"
  echo "Ubiquity exited with code $rc. No success claimed; inspect /var/log/installer/syslog and $LOG_FILE, or run 'nexus-recovery --diagnose'." >&2
  exit "$rc"
fi
