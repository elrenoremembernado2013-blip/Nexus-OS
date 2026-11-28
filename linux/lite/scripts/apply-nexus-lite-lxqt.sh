#!/usr/bin/env bash
# Apply NEXUS Lite LXQt user desktop profile, theme/accent, and wallpaper.
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
WALLPAPER_CLI="${NEXUS_WALLPAPER_CLI:-$REPO_ROOT/linux/mint/nexus-wallpaper-cli.sh}"
if [[ ! -x "$WALLPAPER_CLI" && -x "/usr/local/bin/nexus-wallpaper" ]]; then
  WALLPAPER_CLI="/usr/local/bin/nexus-wallpaper"
fi

XDG_CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
LXQT_DIR="$XDG_CFG/lxqt"
OB_DIR="$XDG_CFG/openbox"
PCMAN_DIR="$XDG_CFG/pcmanfm-qt/lxqt"
STATE_DIR="$XDG_CFG/nexus-os"
PROFILE_FILE="$STATE_DIR/lite-profile"

PROFILE="lite-1g"
THEME="midnight"
APPEARANCE="dark"
CUSTOM_ACCENT=""
WALLPAPER_URL=""
WALLPAPER_FIT="zoom"
WORKSPACES=""
DRY_RUN=false
REVERT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/lite/scripts/apply-nexus-lite-lxqt.sh [OPTIONS]

Configures NEXUS Lite LXQt user desktop settings for a target RAM profile:
  lite-512 | lite-768 | lite-1g | lite-2g | lite-4g

Options:
  --profile NAME         Profile name (default: lite-1g)
  --theme NAME           midnight | nebula | arctic | emerald | solar
  --accent HEX           Optional #RRGGBB accent color
  --appearance MODE      dark | light
  --wallpaper-url URL    HTTPS URL or local image path
  --wallpaper-fit MODE   zoom | scaled | stretched | centered | wallpaper
  --workspaces COUNT     1-8 workspace count
  --revert               Remove user NEXUS Lite LXQt configs
  --dry-run              Print planned actions without writing files
  --help, -h             Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { echo '--profile requires a value' >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --theme) [[ $# -ge 2 ]] || { echo '--theme requires a preset' >&2; exit 2; }; THEME="$2"; shift 2 ;;
    --accent) [[ $# -ge 2 ]] || { echo '--accent requires #RRGGBB' >&2; exit 2; }; CUSTOM_ACCENT="$2"; shift 2 ;;
    --appearance) [[ $# -ge 2 ]] || { echo '--appearance requires dark|light' >&2; exit 2; }; APPEARANCE="$2"; shift 2 ;;
    --wallpaper-url) [[ $# -ge 2 ]] || { echo '--wallpaper-url requires URL or path' >&2; exit 2; }; WALLPAPER_URL="$2"; shift 2 ;;
    --wallpaper-fit) [[ $# -ge 2 ]] || { echo '--wallpaper-fit requires mode' >&2; exit 2; }; WALLPAPER_FIT="$2"; shift 2 ;;
    --workspaces) [[ $# -ge 2 ]] || { echo '--workspaces requires 1-8' >&2; exit 2; }; WORKSPACES="$2"; shift 2 ;;
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
case "$THEME" in
  midnight|nebula|arctic|emerald|solar) ;;
  *) printf 'Invalid --theme: %s\n' "$THEME" >&2; exit 2 ;;
esac
case "$APPEARANCE" in
  dark|light) ;;
  *) printf 'Invalid --appearance: %s\n' "$APPEARANCE" >&2; exit 2 ;;
esac
if [[ -n "$CUSTOM_ACCENT" ]] && ! [[ "$CUSTOM_ACCENT" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
  printf 'Invalid --accent hex: %s\n' "$CUSTOM_ACCENT" >&2; exit 2
fi
if [[ -n "$WORKSPACES" ]] && ! [[ "$WORKSPACES" =~ ^[1-8]$ ]]; then
  printf 'Invalid --workspaces: %s\n' "$WORKSPACES" >&2; exit 2
fi

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

effective_accent="$CUSTOM_ACCENT"
case "$THEME" in
  midnight) effective_accent="${effective_accent:-#66a3ff}" ;;
  nebula) effective_accent="${effective_accent:-#b185ff}" ;;
  arctic) effective_accent="${effective_accent:-#0284c7}"; APPEARANCE="light" ;;
  emerald) effective_accent="${effective_accent:-#34d399}" ;;
  solar) effective_accent="${effective_accent:-#ffad7a}" ;;
esac

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Write NEXUS LXQt configs into %s, %s, %s (profile=%s, theme=%s, accent=%s, appearance=%s)\n' "$LXQT_DIR" "$OB_DIR" "$PCMAN_DIR" "$PROFILE" "$THEME" "$effective_accent" "$APPEARANCE"
  if [[ -n "$WALLPAPER_URL" && -x "$WALLPAPER_CLI" ]]; then
    bash "$WALLPAPER_CLI" apply --url "$WALLPAPER_URL" --fit "$WALLPAPER_FIT" --edition lite-lxqt --dry-run
  fi
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

python3 - "$LXQT_DIR/lxqt.conf" "$effective_accent" "$APPEARANCE" <<'PY'
from pathlib import Path
import re, sys
cfg = Path(sys.argv[1])
accent, appearance = sys.argv[2], sys.argv[3]
text = cfg.read_text(encoding="utf-8")
text = re.sub(r"highlight_color=#[0-9A-Fa-f]{6}", f"highlight_color={accent}", text)
text = re.sub(r"link_color=#[0-9A-Fa-f]{6}", f"link_color={accent}", text)
if appearance == "light":
    text = text.replace("style=Breeze", "style=Fusion")
    text = text.replace("window_color=#0f172a", "window_color=#eef3f8")
    text = text.replace("base_color=#111a2e", "base_color=#ffffff")
    text = text.replace("text_color=#eef4ff", "text_color=#0f172a")
    text = text.replace("window_text_color=#eef4ff", "window_text_color=#0f172a")
cfg.write_text(text, encoding="utf-8")
PY

ws_count=2
if [[ -n "$WORKSPACES" ]]; then
  ws_count="$WORKSPACES"
elif [[ "$PROFILE" == "lite-1g" || "$PROFILE" == "lite-2g" || "$PROFILE" == "lite-4g" ]]; then
  ws_count=4
fi
sed -i "s/<number>2<\/number>/<number>${ws_count}<\/number>/" "$OB_DIR/lxqt-openbox-rc.xml"

printf 'profile=%s\ndesktop=lxqt\ntheme=%s\naccent=%s\nappearance=%s\n' "$PROFILE" "$THEME" "$effective_accent" "$APPEARANCE" > "$PROFILE_FILE"

if [[ -n "$WALLPAPER_URL" && -x "$WALLPAPER_CLI" ]]; then
  bash "$WALLPAPER_CLI" apply --url "$WALLPAPER_URL" --fit "$WALLPAPER_FIT" --edition lite-lxqt
fi

printf 'Applied NEXUS Lite LXQt profile (%s, theme=%s) in %s\n' "$PROFILE" "$THEME" "$LXQT_DIR"
