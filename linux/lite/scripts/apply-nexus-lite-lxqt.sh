#!/usr/bin/env bash
# Apply NEXUS Lite LXQt user desktop profile (lite-512 | lite-768 | lite-1g | lite-2g | lite-4g).
# Runs strictly as the regular desktop user; never disables security/network services.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
LXQT_SRC=""
if [[ -d "$REPO_ROOT/linux/lite/lxqt" ]]; then
  LXQT_SRC="$REPO_ROOT/linux/lite/lxqt"
elif [[ -d "/usr/local/share/nexus-os/lite-lxqt/lxqt" ]]; then
  LXQT_SRC="/usr/local/share/nexus-os/lite-lxqt/lxqt"
fi

XDG_CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
LXQT_DIR="$XDG_CFG/lxqt"
OB_DIR="$XDG_CFG/openbox"
PCMAN_DIR="$XDG_CFG/pcmanfm-qt/lxqt"
STATE_DIR="$XDG_CFG/nexus-os"
PROFILE_FILE="$STATE_DIR/lite-profile"

PROFILE="lite-1g"
DRY_RUN=false
REVERT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/lite/scripts/apply-nexus-lite-lxqt.sh [OPTIONS]

Configures NEXUS Lite LXQt user desktop settings for a target RAM profile:
  lite-512 | lite-768 | lite-1g | lite-2g | lite-4g

Options:
  --profile NAME   Profile name (default: lite-1g)
  --revert         Remove user NEXUS Lite LXQt configs
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
  lite-512|lite-768|lite-1g|lite-2g|lite-4g) ;;
  *) printf 'Invalid --profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

if [[ "$DRY_RUN" == false && "$(id -u)" -eq 0 ]]; then
  echo 'Run apply-nexus-lite-lxqt.sh as your desktop user, not root.' >&2
  exit 1
fi

if [[ "$REVERT" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] Remove NEXUS LXQt configs in %s, %s, %s, and %s\n' "$LXQT_DIR" "$OB_DIR" "$PCMAN_DIR" "$PROFILE_FILE"
  else
    rm -f -- "$LXQT_DIR/lxqt.conf" "$LXQT_DIR/panel.conf" "$LXQT_DIR/session.conf" \
      "$OB_DIR/lxqt-openbox-rc.xml" "$PCMAN_DIR/settings.conf" "$XDG_CFG/qterminal.org/qterminal.ini" "$PROFILE_FILE"
    echo 'Removed user NEXUS Lite LXQt configuration.'
  fi
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Write NEXUS LXQt configs into %s, %s, %s (profile=%s)\n' "$LXQT_DIR" "$OB_DIR" "$PCMAN_DIR" "$PROFILE"
  exit 0
fi

[[ -n "$LXQT_SRC" ]] || { echo 'Missing LXQt template directory (checked repo and /usr/local/share/nexus-os/lite-lxqt/lxqt).' >&2; exit 1; }

mkdir -p -- "$LXQT_DIR" "$OB_DIR" "$PCMAN_DIR" "$XDG_CFG/qterminal.org" "$STATE_DIR"
cp -f -- "$LXQT_SRC/lxqt.conf" "$LXQT_DIR/lxqt.conf"
cp -f -- "$LXQT_SRC/panel.conf" "$LXQT_DIR/panel.conf"
cp -f -- "$LXQT_SRC/session.conf" "$LXQT_DIR/session.conf"
cp -f -- "$LXQT_SRC/openbox-rc.xml" "$OB_DIR/lxqt-openbox-rc.xml"
cp -f -- "$LXQT_SRC/pcmanfm-qt/settings.conf" "$PCMAN_DIR/settings.conf"
cp -f -- "$LXQT_SRC/qterminal.ini" "$XDG_CFG/qterminal.org/qterminal.ini"

if [[ "$PROFILE" == "lite-1g" || "$PROFILE" == "lite-2g" || "$PROFILE" == "lite-4g" ]]; then
  sed -i 's/<number>2<\/number>/<number>4<\/number>/' "$OB_DIR/lxqt-openbox-rc.xml"
fi
printf 'profile=%s\ndesktop=lxqt\n' "$PROFILE" > "$PROFILE_FILE"
printf 'Applied NEXUS Lite LXQt profile (%s) in %s\n' "$PROFILE" "$LXQT_DIR"
