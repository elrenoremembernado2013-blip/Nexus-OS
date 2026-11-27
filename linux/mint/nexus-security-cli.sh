#!/usr/bin/env bash
# NEXUS OS Security & Privacy status and policy helper for Linux Mint 22.3.
# Read-only inspection runs as the regular desktop user; firewall mutations use
# pkexec so system authentication is never bypassed. Never fabricates security
# scores or reports Secure Boot / disk encryption active without verification.
set -euo pipefail

DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-security-cli.sh [OPTIONS] <command> [args...]

Inspects real Linux Mint security & privacy state and manages UFW firewall or
Flatpak per-user sandbox overrides cleanly.

Options:
  --dry-run       Print mutating commands without executing them
  --help, -h      Show this help message

Commands:
  status                                  Print JSON overview (firewall, updates, encryption, secure boot, user, startup)
  firewall <enable|disable>               Enable or disable UFW via pkexec (explicit authentication)
  permissions <flatpak-app-id>            Show real Flatpak sandbox permissions (read-only)
  flatpak-revoke <app-id> <override-flag> Apply a strict allowlisted user Flatpak permission restriction
  flatpak-reset <app-id>                  Reset user Flatpak permission overrides for an app
  startup-list                            List desktop autostart entries in user and system XDG dirs
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
CMD="$1"
shift

validate_flatpak_id() {
  local app_id="$1"
  [[ "$app_id" =~ ^[A-Za-z0-9_.-]{3,128}$ && "$app_id" == *.* ]] || {
    printf 'Invalid Flatpak application ID: %s\n' "$app_id" >&2
    exit 2
  }
}

run_mutating() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

detect_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    if [[ -r /etc/ufw/ufw.conf ]]; then
      if grep -Eq '^ENABLED=yes' /etc/ufw/ufw.conf; then
        printf 'enabled'
      else
        printf 'disabled'
      fi
    else
      printf 'unavailable'
    fi
    return
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    if ufw status 2>/dev/null | grep -qi '^Status: active'; then
      printf 'enabled'
    else
      printf 'disabled'
    fi
  elif [[ -r /etc/ufw/ufw.conf ]]; then
    if grep -Eq '^ENABLED=yes' /etc/ufw/ufw.conf; then
      printf 'enabled'
    else
      printf 'disabled'
    fi
  else
    printf 'unavailable'
  fi
}

detect_secure_boot() {
  local sb_file=""
  for candidate in /sys/firmware/efi/efivars/SecureBoot-*; do
    [[ -r "$candidate" ]] || continue
    sb_file="$candidate"
    break
  done
  if [[ -z "$sb_file" ]]; then
    printf 'unavailable'
    return
  fi
  python3 - "$sb_file" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()
if len(data) >= 5:
    print("enabled" if data[4] == 1 else "disabled")
else:
    print("unavailable")
PY
}

detect_disk_encryption() {
  if ! command -v lsblk >/dev/null 2>&1; then
    printf 'unavailable'
    return
  fi
  if lsblk -dn -o TYPE 2>/dev/null | grep -qx 'crypt'; then
    printf 'enabled'
  else
    printf 'disabled'
  fi
}

detect_unattended_upgrades() {
  if [[ -r /etc/apt/apt.conf.d/20auto-upgrades ]] && grep -Eq 'Unattended-Upgrade\s+"1"' /etc/apt/apt.conf.d/20auto-upgrades; then
    printf 'enabled'
  elif command -v apt >/dev/null 2>&1; then
    printf 'attention_required'
  else
    printf 'unavailable'
  fi
}

list_startup_entries() {
  python3 - <<'PY'
import json, os
from pathlib import Path

dirs = [
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "autostart",
    Path("/etc/xdg/autostart"),
]
items = []
seen = set()
for d in dirs:
    if not d.is_dir():
        continue
    for entry in sorted(d.glob("*.desktop")):
        if entry.name in seen:
            continue
        seen.add(entry.name)
        name = entry.stem
        enabled = True
        try:
            for line in entry.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("Name="):
                    name = line.split("=", 1)[1].strip() or name
                elif line.strip() in ("Hidden=true", "X-GNOME-Autostart-enabled=false"):
                    enabled = False
        except OSError:
            pass
        items.append({"file": entry.name, "name": name, "scope": "user" if str(d).startswith(str(Path.home())) or str(d) == str(dirs[0]) else "system", "enabled": enabled})
print(json.dumps(items))
PY
}

case "$CMD" in
  status)
    fw="$(detect_firewall)"
    sb="$(detect_secure_boot)"
    enc="$(detect_disk_encryption)"
    upd="$(detect_unattended_upgrades)"
    is_root=false
    [[ "$(id -u)" -eq 0 ]] && is_root=true
    current_user="${USER:-$(id -un 2>/dev/null || printf 'unknown')}"
    groups_str="$(id -Gn 2>/dev/null || printf 'unknown')"
    has_sudo=false
    if printf ' %s ' "$groups_str" | grep -Eq ' (sudo|admin|wheel) '; then
      has_sudo=true
    fi
    startup_json="$(list_startup_entries)"
    python3 - "$fw" "$sb" "$enc" "$upd" "$is_root" "$current_user" "$has_sudo" "$startup_json" <<'PY'
import json, sys
fw, sb, enc, upd, is_root, user, has_sudo, startup_raw = sys.argv[1:]
warnings = []
if is_root == "true":
    warnings.append("Running desktop session as root is discouraged; use a standard user account.")
if fw == "disabled":
    warnings.append("UFW firewall is disabled; incoming connections are not filtered by UFW.")
payload = {
    "firewall": {"status": fw, "tool": "ufw"},
    "secure_boot": {"status": sb},
    "disk_encryption": {"status": enc},
    "security_updates": {"status": upd, "note": "Traditional APT packages run unsandboxed; Flatpak apps use portal sandboxes."},
    "account": {"user": user, "is_root": is_root == "true", "in_admin_group": has_sudo == "true"},
    "startup_apps": json.loads(startup_raw),
    "warnings": warnings,
}
print(json.dumps(payload, indent=2))
PY
    ;;

  firewall)
    [[ $# -eq 1 ]] || { echo 'firewall requires enable or disable' >&2; exit 2; }
    action="$1"
    if [[ "$DRY_RUN" == false ]]; then
      command -v ufw >/dev/null 2>&1 || { echo 'ufw is not installed on this host.' >&2; exit 1; }
      command -v pkexec >/dev/null 2>&1 || { echo 'pkexec (PolicyKit) is required to configure UFW safely.' >&2; exit 1; }
    fi
    case "$action" in
      enable)
        run_mutating pkexec ufw default deny incoming
        run_mutating pkexec ufw default allow outgoing
        run_mutating pkexec ufw --force enable
        ;;
      disable)
        run_mutating pkexec ufw disable
        ;;
      *)
        printf 'Invalid firewall action: %s (expected enable or disable)\n' "$action" >&2
        exit 2
        ;;
    esac
    ;;

  permissions)
    [[ $# -eq 1 ]] || { echo 'permissions requires <flatpak-app-id>' >&2; exit 2; }
    app_id="$1"
    validate_flatpak_id "$app_id"
    command -v flatpak >/dev/null 2>&1 || { echo 'flatpak is not installed on this host.' >&2; exit 1; }
    flatpak info --show-permissions -- "$app_id"
    ;;

  flatpak-revoke)
    [[ $# -eq 2 ]] || { echo 'flatpak-revoke requires <flatpak-app-id> <override-flag>' >&2; exit 2; }
    app_id="$1"
    flag="$2"
    validate_flatpak_id "$app_id"
    case "$flag" in
      --nofilesystem=home|--nofilesystem=host|--nosocket=x11|--nosocket=wayland|--unshare=network|--nodevice=all) ;;
      *)
        printf 'Unsupported Flatpak restriction flag: %s\n' "$flag" >&2
        exit 2
        ;;
    esac
    if [[ "$DRY_RUN" == false ]]; then
      command -v flatpak >/dev/null 2>&1 || { echo 'flatpak is not installed on this host.' >&2; exit 1; }
    fi
    run_mutating flatpak override --user "$flag" "$app_id"
    ;;

  flatpak-reset)
    [[ $# -eq 1 ]] || { echo 'flatpak-reset requires <flatpak-app-id>' >&2; exit 2; }
    app_id="$1"
    validate_flatpak_id "$app_id"
    if [[ "$DRY_RUN" == false ]]; then
      command -v flatpak >/dev/null 2>&1 || { echo 'flatpak is not installed on this host.' >&2; exit 1; }
    fi
    run_mutating flatpak override --user --reset "$app_id"
    ;;

  startup-list)
    list_startup_entries
    ;;

  *)
    printf 'Unknown command: %s\n' "$CMD" >&2
    usage >&2
    exit 2
    ;;
esac
