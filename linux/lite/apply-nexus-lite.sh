#!/usr/bin/env bash
# Apply NEXUS Lite / Standard user desktop profile (lite-512 | lite-1g | standard-2g).
# Runs strictly as the regular desktop user; never disables security/network services.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OPENBOX_SRC=""
if [[ -d "$SCRIPT_DIR/openbox" ]]; then
  OPENBOX_SRC="$SCRIPT_DIR/openbox"
elif [[ -d "/usr/local/share/nexus-os/lite/openbox" ]]; then
  OPENBOX_SRC="/usr/local/share/nexus-os/lite/openbox"
fi

OPENBOX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openbox"
TINT2_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tint2"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nexus-os"
PROFILE_FILE="$STATE_DIR/lite-profile"

PROFILE="lite-512"
DRY_RUN=false
REVERT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/lite/apply-nexus-lite.sh [OPTIONS]

Configures one of three NEXUS OS operating profiles:
  lite-512     NEXUS Lite — 512 MB Experimental (Openbox + tint2, zero compositor, 2 workspaces)
  lite-1g      NEXUS Lite — 1 GB (Openbox + tint2 + nm-applet, 4 workspaces)
  standard-2g  NEXUS Standard — 2 GB+ (delegates to Cinnamon/Xfce desktop helpers)

Options:
  --profile NAME   lite-512 | lite-1g | standard-2g (default: lite-512)
  --revert         Remove user Openbox/tint2 NEXUS Lite configs
  --dry-run        Print planned actions without writing files
  --help, -h       Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { echo '--profile requires a value' >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --revert) REVERT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$PROFILE" in
  lite-512|lite-1g|standard-2g) ;;
  *) printf 'Invalid --profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

if [[ "$DRY_RUN" == false && "$(id -u)" -eq 0 ]]; then
  echo 'Run apply-nexus-lite.sh as your desktop user, not root.' >&2
  exit 1
fi

if [[ "$REVERT" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] Remove %s/rc.xml %s/menu.xml %s/autostart %s/tint2rc %s\n' "$OPENBOX_DIR" "$OPENBOX_DIR" "$OPENBOX_DIR" "$TINT2_DIR" "$PROFILE_FILE"
  else
    rm -f -- "$OPENBOX_DIR/rc.xml" "$OPENBOX_DIR/menu.xml" "$OPENBOX_DIR/autostart" "$TINT2_DIR/tint2rc" "$PROFILE_FILE"
    echo 'Removed user NEXUS Lite Openbox/tint2 configuration.'
  fi
  exit 0
fi

if [[ "$PROFILE" == "standard-2g" ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    echo '[dry-run] Delegate standard-2g profile to Cinnamon/Xfce desktop configuration'
    exit 0
  fi
  if command -v cinnamon-session >/dev/null 2>&1; then
    if [[ -x "$REPO_ROOT/linux/cinnamon/apply-nexus-cinnamon.sh" ]]; then
      exec bash "$REPO_ROOT/linux/cinnamon/apply-nexus-cinnamon.sh" --profile balanced
    elif command -v nexus-apply-cinnamon >/dev/null 2>&1; then
      exec nexus-apply-cinnamon --profile balanced
    fi
  else
    if [[ -x "$REPO_ROOT/linux/mint/apply-nexus-xfce.sh" ]]; then
      exec bash "$REPO_ROOT/linux/mint/apply-nexus-xfce.sh"
    elif command -v nexus-apply-xfce >/dev/null 2>&1; then
      exec nexus-apply-xfce
    fi
  fi
  echo 'Cinnamon/Xfce helper not found; install NEXUS Standard desktop tools first.' >&2
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Write Openbox rc.xml/menu.xml/autostart in %s and tint2rc in %s (profile=%s)\n' "$OPENBOX_DIR" "$TINT2_DIR" "$PROFILE"
  printf '[dry-run] Record profile=%s in %s\n' "$PROFILE" "$PROFILE_FILE"
  exit 0
fi

[[ -n "$OPENBOX_SRC" ]] || { echo 'Missing Openbox template directory (checked repo and /usr/local/share/nexus-os/lite/openbox).' >&2; exit 1; }

mkdir -p -- "$OPENBOX_DIR" "$TINT2_DIR" "$STATE_DIR"
cp -f -- "$OPENBOX_SRC/rc.xml" "$OPENBOX_DIR/rc.xml"
cp -f -- "$OPENBOX_SRC/menu.xml" "$OPENBOX_DIR/menu.xml"
install -m 0755 "$OPENBOX_SRC/autostart" "$OPENBOX_DIR/autostart"
cp -f -- "$OPENBOX_SRC/tint2rc" "$TINT2_DIR/tint2rc"

if [[ "$PROFILE" == "lite-1g" ]]; then
  sed -i 's/<number>2<\/number>/<number>4<\/number>/' "$OPENBOX_DIR/rc.xml"
fi
printf 'profile=%s\n' "$PROFILE" > "$PROFILE_FILE"
printf 'Applied NEXUS Lite profile (%s) in %s\n' "$PROFILE" "$OPENBOX_DIR"
